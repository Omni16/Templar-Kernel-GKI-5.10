#!/usr/bin/env bash
#
# Integrate BakaSU KernelSU + SUSFS into a 5.10 GKI tree.
#
# Hook mode: SUSFS Inline Hook (CONFIG_KSU_SUSFS).  This is BakaSU's
# manual-hook-like mode and is mutually exclusive with KSU_MANUAL_HOOK and
# KSU_TRACEPOINT_HOOK.  SUSFS patch 50 supplies the execve/open/stat/read/
# input/setuid/reboot hooks, so CONFIG_KPROBES can stay disabled.
#
# The BakaSU source is fetched at a pinned commit.  SUSFS patch 50 and its
# three source files are vendored in patches/susfs so the build does not
# depend on a moving GitLab branch.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

BAKASU_COMMIT="${BAKASU_COMMIT:-5d6d1843c8937f5ff2a145dc89a0cf46030ae6f8}"
BAKASU_REPO="${BAKASU_REPO:-https://github.com/Baka-SU/BakaSU.git}"
KSU_DIR="${KSU_DIR:-$ROOT/KernelSU}"
SUSFS_DIR="${SUSFS_DIR:-$ROOT/patches/susfs}"
KCONFIG_PATCH="${KCONFIG_PATCH:-$ROOT/patches/0001-kconfig-allow-zyomi16-options.patch}"
INFO_FILE="${INFO_FILE:-$ROOT/integration-info.txt}"

fail() {
    echo "ERROR: $*" >&2
    exit 1
}

note() {
    echo "==> $*"
}

check_no_rejects() {
    local rejects
    rejects="$(find . -name '*.rej' -print -quit)"
    if [ -n "$rejects" ]; then
        find . -name '*.rej' -print >&2
        fail "patch left reject files in the source tree"
    fi
}

[ -f Makefile ] || fail "run this script from the kernel tree"
grep -q '^VERSION = 5$' Makefile || fail "this script expects a 5.x kernel"
grep -q '^PATCHLEVEL = 10$' Makefile || fail "this script expects a 5.10 kernel"

# ---------------------------------------------------------------------------
# 1. BakaSU (KernelSU)
# ---------------------------------------------------------------------------
if [ ! -d "$KSU_DIR/.git" ]; then
    note "cloning BakaSU at $BAKASU_COMMIT"
    rm -rf "$KSU_DIR"
    git clone --filter=blob:none --no-checkout --single-branch \
        "$BAKASU_REPO" "$KSU_DIR"
fi

git -C "$KSU_DIR" sparse-checkout init --cone
# kernel/include/uapi is a symlink to the repo's top-level uapi/ directory,
# so the sparse checkout must include both.
git -C "$KSU_DIR" sparse-checkout set kernel uapi

if ! git -C "$KSU_DIR" cat-file -e "${BAKASU_COMMIT}^{commit}" 2>/dev/null; then
    note "fetching pinned BakaSU commit"
    git -C "$KSU_DIR" fetch --tags --force origin "$BAKASU_COMMIT"
fi

git -C "$KSU_DIR" checkout --force "$BAKASU_COMMIT"
[ "$(git -C "$KSU_DIR" rev-parse HEAD)" = "$BAKASU_COMMIT" ] \
    || fail "BakaSU checkout is not at the pinned commit"
[ -f "$KSU_DIR/kernel/Kbuild" ] || fail "BakaSU kernel/Kbuild is missing"
[ -f "$KSU_DIR/kernel/Kconfig" ] || fail "BakaSU kernel/Kconfig is missing"
for header in supercall.h app_profile.h feature.h selinux.h sulog.h ksu.h; do
    [ -f "$KSU_DIR/uapi/$header" ] \
        || fail "BakaSU uapi/$header is missing (sparse checkout must include uapi)"
done

# BakaSU's Kbuild insists on a real git repository at KernelSU/.git.  The
# sparse clone above keeps that requirement while only checking out kernel/.
if [ -e drivers/kernelsu ] && [ ! -L drivers/kernelsu ]; then
    fail "drivers/kernelsu exists and is not a symlink"
fi
ln -sfn ../KernelSU/kernel drivers/kernelsu

if ! grep -q 'CONFIG_KSU.*kernelsu' drivers/Makefile; then
    printf '\nobj-$(CONFIG_KSU) += kernelsu/\n' >> drivers/Makefile
fi

if ! grep -q 'source "drivers/kernelsu/Kconfig"' drivers/Kconfig; then
    python3 - <<'PY'
from pathlib import Path

path = Path("drivers/Kconfig")
lines = path.read_text().splitlines()
positions = [i for i, line in enumerate(lines) if line.strip() == "endmenu"]
if not positions:
    raise SystemExit("drivers/Kconfig: no endmenu found")
lines.insert(positions[-1], 'source "drivers/kernelsu/Kconfig"')
path.write_text("\n".join(lines) + "\n")
PY
fi

# ---------------------------------------------------------------------------
# 2. Small Kconfig changes needed to make the requested options reachable
# ---------------------------------------------------------------------------
# AUDITSYSCALL is def_bool y upstream and SLUB_DEBUG defaults to y when
# EXPERT is disabled.  Both are made user-selectable so the fragment can turn
# them off without enabling DEBUG_KERNEL/EXPERT.
if ! grep -A3 '^config AUDITSYSCALL$' init/Kconfig | grep -q 'bool "Audit syscall support"'; then
    patch -p1 --forward --fuzz=3 --no-backup-if-mismatch < "$KCONFIG_PATCH" || true
fi

grep -A3 '^config AUDITSYSCALL$' init/Kconfig | grep -q 'bool "Audit syscall support"' \
    || fail "AUDITSYSCALL Kconfig change was not applied"
grep -A3 '^config SLUB_DEBUG$' init/Kconfig | grep -q 'default n' \
    || fail "SLUB_DEBUG Kconfig change was not applied"
grep -A3 '^config KALLSYMS_ALL$' init/Kconfig | grep -q 'depends on KALLSYMS$' \
    || fail "KALLSYMS_ALL Kconfig change was not applied"
check_no_rejects

# ---------------------------------------------------------------------------
# 3. SUSFS
# ---------------------------------------------------------------------------
[ -f "$SUSFS_DIR/50_add_susfs_in_gki-android12-5.10.patch" ] \
    || fail "SUSFS patch is missing"
[ -f "$SUSFS_DIR/fs/susfs.c" ] || fail "SUSFS fs/susfs.c is missing"
[ -f "$SUSFS_DIR/include/linux/susfs.h" ] || fail "SUSFS susfs.h is missing"
[ -f "$SUSFS_DIR/include/linux/susfs_def.h" ] || fail "SUSFS susfs_def.h is missing"

cp -f "$SUSFS_DIR/fs/susfs.c" fs/susfs.c
cp -f "$SUSFS_DIR/include/linux/susfs.h" include/linux/susfs.h
cp -f "$SUSFS_DIR/include/linux/susfs_def.h" include/linux/susfs_def.h

if ! grep -q 'susfs' fs/Makefile; then
    patch -p1 --forward --fuzz=3 --no-backup-if-mismatch \
        < "$SUSFS_DIR/50_add_susfs_in_gki-android12-5.10.patch" || true
fi

grep -q 'susfs' fs/Makefile || fail "SUSFS fs/Makefile entry is missing"
grep -q 'susfs_init' fs/susfs.c || fail "SUSFS source was not installed"
check_no_rejects

# ---------------------------------------------------------------------------
# 4. Verify the hooks BakaSU's SUSFS inline mode requires
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

{
    echo "BakaSU commit: $BAKASU_COMMIT"
    echo "BakaSU describe: $(git -C "$KSU_DIR" describe --tags --always 2>/dev/null || echo unknown)"
    echo "BakaSU version code: $(($(git -C "$KSU_DIR" rev-list --count HEAD) + 30700))"
    echo "SUSFS patch: patches/susfs/50_add_susfs_in_gki-android12-5.10.patch"
    echo "SUSFS mode: CONFIG_KSU_SUSFS (inline hooks, no kprobes)"
    echo "KernelSU hooks: OK"
} | tee "$INFO_FILE"

note "KernelSU + SUSFS integration complete"
