#!/usr/bin/env bash
#
# Integrate BakaSU KernelSU (main HEAD) and the latest SUSFS for 5.10 GKI.
#
# BakaSU is installed with the official setup script from
# https://bakasu.org/guide/build:
#
#   curl -LSs "https://raw.githubusercontent.com/Baka-SU/BakaSU/main/kernel/setup.sh" | bash
#
# The script clones BakaSU into ./KernelSU, checks out main, pulls the latest
# commit, symlinks drivers/kernelsu and adds the Makefile/Kconfig entries.  The
# commit and KernelSU version are recorded for the workflow log/artifact name.
#
# SUSFS is fetched from the branch that matches this kernel
# (gki-android12-5.10) at build time.  Its kernel-side patch 50 and the three
# source/header files are installed exactly as the SUSFS README instructs.
# The KernelSU-side 10_enable_susfs_for_ksu.patch is deliberately NOT applied:
# BakaSU already contains the SUSFS support, and applying that patch on top of
# BakaSU conflicts with its own sucompat/SUSFS code.
#
# Hook mode: SUSFS Inline Hook (CONFIG_KSU_SUSFS).  It supplies the
# execve/open/stat/read/input/setuid/reboot hooks, so CONFIG_KPROBES,
# CONFIG_KSU_MANUAL_HOOK and CONFIG_KSU_TRACEPOINT_HOOK stay disabled.  Do not
# add a hand-written manual sucompat hook in this mode.
#
# If patch 50 is rejected, the script prints every rejected file and hunk and
# exits without forcing or fuzzing the patch.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

BAKASU_REPO="${BAKASU_REPO:-https://github.com/Baka-SU/BakaSU.git}"
BAKASU_SETUP_URL="${BAKASU_SETUP_URL:-https://raw.githubusercontent.com/Baka-SU/BakaSU/main/kernel/setup.sh}"
SUSFS_REPO="${SUSFS_REPO:-https://gitlab.com/simonpunk/susfs4ksu.git}"
SUSFS_BRANCH="${SUSFS_BRANCH:-gki-android12-5.10}"
KSU_DIR="$ROOT/KernelSU"
SUSFS_DIR="${SUSFS_DIR:-$ROOT/susfs4ksu}"
SUSFS_EXTRA="${SUSFS_EXTRA:-$ROOT/configs/ksu-susfs-extra.fragment}"
KCONFIG_PATCH="${KCONFIG_PATCH:-$ROOT/patches/0001-kconfig-allow-zyomi16-options.patch}"
SUSFS_LOGFIX_PATCH="${SUSFS_LOGFIX_PATCH:-$ROOT/patches/0002-susfs-log-off-ratelimited-macros.patch}"
INFO_FILE="${INFO_FILE:-$ROOT/integration-info.txt}"
OUT_DIR="${OUT_DIR:-$ROOT/out}"
PATCH_LOG="$OUT_DIR/susfs-patch.log"
SETUP_LOG="$OUT_DIR/bakasu-setup.log"
REJECT_DIR="$ROOT/susfs-rejects"
REJECT_NAME="$(basename "$REJECT_DIR")"

fail() {
    echo "ERROR: $*" >&2
    exit 1
}

note() {
    echo "==> $*"
}

find_rejects() {
    # Do not descend into the collected reject copies; otherwise `find` sees
    # the files it is copying and creates nested susfs-rejects/susfs-rejects/.
    find . -path "./$REJECT_NAME" -prune -o -name '*.rej' "$@"
}

show_rejects() {
    local rejects
    rejects="$(find_rejects -print)"
    if [ -n "$rejects" ]; then
        echo "Rejected files and hunks:" >&2
        while IFS= read -r rej; do
            echo "--- $rej ---" >&2
            cat "$rej" >&2
        done <<< "$rejects"
    fi
}

check_no_rejects() {
    local rejects
    rejects="$(find_rejects -print -quit)"
    if [ -n "$rejects" ]; then
        find_rejects -print >&2
        show_rejects
        fail "patch left reject files in the source tree"
    fi
}

save_reject_report() {
    local message="$1"
    local patch_file="$2"
    local log_file="$3"
    local rc="$4"

    {
        echo "ERROR: $message (exit code $rc)"
        echo "Patch: $patch_file"
        echo "Patch output (failed files/hunks):"
        cat "$log_file"
        echo ""
        show_rejects
    } | tee "$OUT_DIR/susfs-rejects.txt" >&2
    find_rejects -exec cp --parents {} "$REJECT_DIR/" \;
    cp "$log_file" "$REJECT_DIR/" 2>/dev/null || true
}

[ -f Makefile ] || fail "run this script from the kernel tree"
grep -q '^VERSION = 5$' Makefile || fail "this script expects a 5.x kernel"
grep -q '^PATCHLEVEL = 10$' Makefile || fail "this script expects a 5.10 kernel"

mkdir -p "$OUT_DIR"

# ---------------------------------------------------------------------------
# 1. BakaSU main HEAD via the official setup script
# ---------------------------------------------------------------------------
note "running the official BakaSU setup script (main branch)"
curl -fLSs --retry 3 --retry-delay 5 -o "$OUT_DIR/bakasu-setup.sh" "$BAKASU_SETUP_URL"
sha256sum "$OUT_DIR/bakasu-setup.sh" | tee "$OUT_DIR/bakasu-setup.sha256"
bash "$OUT_DIR/bakasu-setup.sh" 2>&1 | tee "$SETUP_LOG"

[ -d "$KSU_DIR/.git" ] || fail "the official setup script did not create KernelSU/.git"
[ -L drivers/kernelsu ] || fail "the official setup script did not create drivers/kernelsu"
[ -f "$KSU_DIR/kernel/Kbuild" ] || fail "BakaSU kernel/Kbuild is missing"
[ -f "$KSU_DIR/kernel/Kconfig" ] || fail "BakaSU kernel/Kconfig is missing"

KSU_BRANCH="$(git -C "$KSU_DIR" branch --show-current)"
[ "$KSU_BRANCH" = "main" ] || fail "BakaSU is on '$KSU_BRANCH', expected main"
[ -z "$(git -C "$KSU_DIR" status --porcelain --untracked-files=no)" ] \
    || fail "BakaSU worktree has tracked modifications after the official setup script"

BAKASU_COMMIT="$(git -C "$KSU_DIR" rev-parse HEAD)"
BAKASU_SHORT="${BAKASU_COMMIT:0:8}"
KSU_COMMIT_COUNT="$(git -C "$KSU_DIR" rev-list --count HEAD)"
KSU_VERSION="$((30000 + KSU_COMMIT_COUNT + 700))"
KSU_TAG="$(git -C "$KSU_DIR" describe --abbrev=0 --tags 2>/dev/null || echo unknown)"
# BakaSU's Kconfig default is KSU_FULL_NAME_FORMAT="%TAG_NAME%-%COMMIT_SHA%".
KSU_VERSION_FULL="${KSU_TAG}-${BAKASU_SHORT}"

[ "$(git -C "$KSU_DIR" rev-parse HEAD)" = "$BAKASU_COMMIT" ] \
    || fail "BakaSU checkout changed while recording its version"
for header in supercall.h app_profile.h feature.h selinux.h sulog.h ksu.h; do
    [ -f "$KSU_DIR/uapi/$header" ] || fail "BakaSU uapi/$header is missing"
done

note "BakaSU main HEAD: $BAKASU_COMMIT"
note "KernelSU version code: $KSU_VERSION ($KSU_VERSION_FULL)"

# ---------------------------------------------------------------------------
# 2. Small Kconfig changes needed to make the requested options reachable
# ---------------------------------------------------------------------------
# AUDITSYSCALL is def_bool y upstream and SLUB_DEBUG defaults to y when
# EXPERT is disabled.  Both are made user-selectable so the fragment can turn
# them off without enabling DEBUG_KERNEL/EXPERT.
if ! grep -A3 '^config AUDITSYSCALL$' init/Kconfig | grep -q 'bool "Audit syscall support"'; then
    note "applying the Zyomi16 Kconfig patch"
    if ! patch -p1 --fuzz=0 --no-backup-if-mismatch \
            < "$KCONFIG_PATCH" > "$OUT_DIR/kconfig-patch.log" 2>&1; then
        cat "$OUT_DIR/kconfig-patch.log" >&2
        show_rejects
        fail "Zyomi16 Kconfig patch failed"
    fi
    cat "$OUT_DIR/kconfig-patch.log"
fi

grep -A3 '^config AUDITSYSCALL$' init/Kconfig | grep -q 'bool "Audit syscall support"' \
    || fail "AUDITSYSCALL Kconfig change was not applied"
grep -A3 '^config SLUB_DEBUG$' init/Kconfig | grep -q 'default n' \
    || fail "SLUB_DEBUG Kconfig change was not applied"
grep -A3 '^config KALLSYMS_ALL$' init/Kconfig | grep -q 'depends on KALLSYMS$' \
    || fail "KALLSYMS_ALL Kconfig change was not applied"
check_no_rejects

# ---------------------------------------------------------------------------
# 3. Latest SUSFS for gki-android12-5.10
# ---------------------------------------------------------------------------
note "fetching SUSFS $SUSFS_BRANCH from $SUSFS_REPO"
rm -rf "$SUSFS_DIR"
git clone --depth 1 --branch "$SUSFS_BRANCH" "$SUSFS_REPO" "$SUSFS_DIR" \
    2>&1 | tee "$OUT_DIR/susfs-clone.log"

SUSFS_COMMIT="$(git -C "$SUSFS_DIR" rev-parse HEAD)"
SUSFS_VERSION="$(sed -n 's/^#define SUSFS_VERSION "\(.*\)"/\1/p' \
    "$SUSFS_DIR/kernel_patches/include/linux/susfs.h")"
[ -n "$SUSFS_VERSION" ] || fail "could not read SUSFS_VERSION from the SUSFS tree"
note "SUSFS $SUSFS_VERSION at $SUSFS_COMMIT"

SUSFS_PATCH="$SUSFS_DIR/kernel_patches/50_add_susfs_in_gki-android12-5.10.patch"
[ -f "$SUSFS_PATCH" ] || fail "SUSFS patch 50 is missing"
[ -f "$SUSFS_DIR/kernel_patches/fs/susfs.c" ] || fail "SUSFS fs/susfs.c is missing"
[ -f "$SUSFS_DIR/kernel_patches/include/linux/susfs.h" ] || fail "SUSFS susfs.h is missing"
[ -f "$SUSFS_DIR/kernel_patches/include/linux/susfs_def.h" ] || fail "SUSFS susfs_def.h is missing"

cp -f "$SUSFS_DIR/kernel_patches/fs/susfs.c" fs/susfs.c
cp -f "$SUSFS_DIR/kernel_patches/include/linux/susfs.h" include/linux/susfs.h
cp -f "$SUSFS_DIR/kernel_patches/include/linux/susfs_def.h" include/linux/susfs_def.h

mkdir -p "$REJECT_DIR"
rm -rf "${REJECT_DIR:?}"/*

# ---------------------------------------------------------------------------
# 3b. Keep CONFIG_KSU_SUSFS_ENABLE_LOG=n buildable
# ---------------------------------------------------------------------------
# SUSFS v2.4.0 calls SUSFS_LOGI_RL() unconditionally in fs/susfs.c but only
# defines the ratelimited logging macros when CONFIG_KSU_SUSFS_ENABLE_LOG is
# enabled.  The fix adds guarded no-op definitions after the logging block, so
# they are used only when the enabled branch did not provide them.  This is a
# separate, strictly applied compatibility patch; SUSFS patch 50 itself is
# never modified, forced or fuzzed.
if [ "$(grep -c '^#define SUSFS_LOGI_RL' fs/susfs.c)" -lt 2 ]; then
    [ -f "$SUSFS_LOGFIX_PATCH" ] || fail "SUSFS ENABLE_LOG=n compatibility patch is missing"
    note "applying the SUSFS ENABLE_LOG=n compatibility fix (strict, fuzz=0)"
    set +e
    patch -p1 --fuzz=0 --no-backup-if-mismatch \
        < "$SUSFS_LOGFIX_PATCH" > "$OUT_DIR/susfs-logfix.log" 2>&1
    logfix_rc=$?
    set -e
    if [ "$logfix_rc" -ne 0 ]; then
        save_reject_report "SUSFS ENABLE_LOG=n compatibility fix failed" \
            "$SUSFS_LOGFIX_PATCH" "$OUT_DIR/susfs-logfix.log" "$logfix_rc"
        fail "SUSFS ENABLE_LOG=n compatibility fix rejected; review the .rej files"
    fi
    cat "$OUT_DIR/susfs-logfix.log"
    SUSFS_LOGFIX_STATUS="applied ($(basename "$SUSFS_LOGFIX_PATCH"))"
else
    SUSFS_LOGFIX_STATUS="not needed (upstream already defines the ratelimited macros)"
fi
[ "$(grep -c '^#define SUSFS_LOGI_RL' fs/susfs.c)" -ge 2 ] \
    || fail "SUSFS_LOGI_RL is still missing a logging-disabled definition"
[ "$(grep -c '^#define SUSFS_LOGE_RL' fs/susfs.c)" -ge 2 ] \
    || fail "SUSFS_LOGE_RL is still missing a logging-disabled definition"

# ---------------------------------------------------------------------------
# 4. Apply patch 50 strictly.  Never force or fuzz a rejected patch.
# ---------------------------------------------------------------------------
# BakaSU already has the SUSFS/KernelSU bridge, so the SUSFS
# KernelSU/10_enable_susfs_for_ksu.patch is intentionally not applied.
if ! grep -q 'susfs' fs/Makefile; then
    note "applying SUSFS patch 50 (strict, fuzz=0)"
    set +e
    patch -p1 --fuzz=0 --no-backup-if-mismatch < "$SUSFS_PATCH" 2>&1 | tee "$PATCH_LOG"
    patch_rc="${PIPESTATUS[0]}"
    set -e
    if [ "$patch_rc" -ne 0 ]; then
        save_reject_report "SUSFS patch 50 failed" "$SUSFS_PATCH" "$PATCH_LOG" "$patch_rc"
        fail "SUSFS patch 50 rejected; the source tree may have changed"
    fi
fi

grep -q 'susfs' fs/Makefile || fail "SUSFS fs/Makefile entry is missing"
grep -q 'susfs_init' fs/susfs.c || fail "SUSFS source was not installed"
check_no_rejects

# ---------------------------------------------------------------------------
# 5. Verify the hooks BakaSU's SUSFS inline mode requires
# ---------------------------------------------------------------------------
# BakaSU checks these at compile time.  Fail early with a readable error if a
# source branch has moved or the patch was only partially applied.
hooks="
fs/exec.c:ksu_handle_execveat
fs/open.c:ksu_handle_faccessat
fs/read_write.c:ksu_handle_sys_read
fs/stat.c:ksu_handle_stat
fs/stat.c:ksu_handle_vfs_fstat
kernel/sys.c:ksu_handle_setresuid
kernel/reboot.c:ksu_handle_sys_reboot
drivers/input/input.c:ksu_handle_input_handle_event
"

while IFS=: read -r file symbol; do
    [ -n "$file" ] || continue
    grep -q "$symbol" "$file" || fail "missing hook $symbol in $file"
done <<EOF
$hooks
EOF

# These old BakaSU/KernelSU hook names are not used by the SUSFS inline mode.
for symbol in ksu_vfs_read_hook ksu_input_hook ksu_execveat_hook ksu_init_rc_hook; do
    if grep -Rqs "$symbol" fs kernel drivers/input 2>/dev/null; then
        fail "unexpected legacy hook $symbol found"
    fi
done

# ---------------------------------------------------------------------------
# 6. Optional SUSFS options that depend on the BakaSU version
# ---------------------------------------------------------------------------
mkdir -p "$(dirname "$SUSFS_EXTRA")"
{
    echo "# Generated by scripts/apply-ksu-susfs.sh from BakaSU main."
    if grep -qx 'config KSU_SUSFS_HAS_MAGIC_MOUNT' "$KSU_DIR/kernel/Kconfig"; then
        echo 'CONFIG_KSU_SUSFS_HAS_MAGIC_MOUNT=y'
    else
        echo '# CONFIG_KSU_SUSFS_HAS_MAGIC_MOUNT does not exist in this BakaSU tree'
    fi
    if grep -qx 'config KSU_SUSFS_SUS_SU' "$KSU_DIR/kernel/Kconfig"; then
        # SUSFS inline hook mode: SUS_SU must stay off if the symbol exists.
        echo '# CONFIG_KSU_SUSFS_SUS_SU is not set'
    else
        echo '# CONFIG_KSU_SUSFS_SUS_SU does not exist in this BakaSU tree'
    fi
} > "$SUSFS_EXTRA"

if grep -qx 'config KSU_SUSFS_HAS_MAGIC_MOUNT' "$KSU_DIR/kernel/Kconfig"; then
    HAS_MAGIC_MOUNT="present, requested y"
else
    HAS_MAGIC_MOUNT="not present in this BakaSU tree"
fi

if grep -qx 'config KSU_SUSFS_SUS_SU' "$KSU_DIR/kernel/Kconfig"; then
    SUS_SU="present, forced n (inline hook mode)"
else
    SUS_SU="not present in this BakaSU tree"
fi

# ---------------------------------------------------------------------------
# 7. Integration record
# ---------------------------------------------------------------------------
{
    echo "BakaSU repo: $BAKASU_REPO"
    echo "BakaSU branch: main"
    echo "BakaSU commit: $BAKASU_COMMIT"
    echo "BakaSU commit short: $BAKASU_SHORT"
    echo "BakaSU setup script: $BAKASU_SETUP_URL"
    echo "BakaSU setup script sha256: $(cut -d' ' -f1 "$OUT_DIR/bakasu-setup.sha256")"
    echo "KernelSU version code: $KSU_VERSION"
    echo "KernelSU version full: $KSU_VERSION_FULL"
    echo "KernelSU tag: $KSU_TAG"
    echo "KernelSU commit count: $KSU_COMMIT_COUNT"
    echo "SUSFS repo: $SUSFS_REPO"
    echo "SUSFS branch: $SUSFS_BRANCH"
    echo "SUSFS commit: $SUSFS_COMMIT"
    echo "SUSFS version: $SUSFS_VERSION"
    echo "SUSFS patch: 50_add_susfs_in_gki-android12-5.10.patch"
    echo "SUSFS log-off fix: $SUSFS_LOGFIX_STATUS"
    echo "SUSFS HAS_MAGIC_MOUNT: $HAS_MAGIC_MOUNT"
    echo "SUSFS SUS_SU: $SUS_SU"
    echo "Hook mode: SUSFS Inline Hook (CONFIG_KSU_SUSFS=y)"
    echo "Manual hook: disabled (CONFIG_KSU_MANUAL_HOOK=n)"
    echo "Tracepoint hook: disabled (CONFIG_KSU_TRACEPOINT_HOOK=n)"
    echo "KPROBES: disabled"
    echo "KernelSU hooks: OK"
} | tee "$INFO_FILE"

note "KernelSU + SUSFS integration complete"
