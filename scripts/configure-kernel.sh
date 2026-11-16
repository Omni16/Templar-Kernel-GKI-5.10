#!/usr/bin/env bash
#
# Create the final .config from the extracted marble GSI config plus the
# Zyomi16 fragment, then run olddefconfig and audit the requested options.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="${OUT_DIR:-$ROOT/out}"
LTO_MODE="${LTO_MODE:-full}"
BASE_CONFIG="${BASE_CONFIG:-$ROOT/configs/base-marble-5.10.236.config}"
FRAGMENT="${FRAGMENT:-$ROOT/configs/zyomi16-marble.fragment}"
SUSFS_EXTRA="${SUSFS_EXTRA:-$ROOT/configs/ksu-susfs-extra.fragment}"
BUILD_FIXES="${BUILD_FIXES:-$ROOT/configs/build-fixes.fragment}"
EFFECTIVE_FRAGMENT="$OUT_DIR/effective-requested.fragment"

case "$LTO_MODE" in
    full|thin) ;;
    *) echo "ERROR: LTO_MODE must be full or thin (got: $LTO_MODE)" >&2; exit 1 ;;
esac

[ -f "$BASE_CONFIG" ] || { echo "ERROR: missing $BASE_CONFIG" >&2; exit 1; }
[ -f "$FRAGMENT" ] || { echo "ERROR: missing $FRAGMENT" >&2; exit 1; }
[ -f "$BUILD_FIXES" ] || { echo "ERROR: missing $BUILD_FIXES" >&2; exit 1; }

# apply-ksu-susfs.sh writes provenance/reject logs into out/.  Keep them when
# the configuration directory is recreated so the workflow can upload them.
PRESERVE_DIR="$ROOT/.integration-preserve"
rm -rf "$PRESERVE_DIR"
mkdir -p "$PRESERVE_DIR"
shopt -s nullglob
for file in "$OUT_DIR"/*.log "$OUT_DIR"/bakasu-setup.sh \
            "$OUT_DIR"/bakasu-setup.sha256 "$OUT_DIR"/susfs-rejects.txt; do
    [ -f "$file" ] || continue
    cp -a "$file" "$PRESERVE_DIR/"
done
shopt -u nullglob

rm -rf "$OUT_DIR"
mkdir -p "$OUT_DIR"
cp "$BASE_CONFIG" "$OUT_DIR/.config"

shopt -s nullglob
for file in "$PRESERVE_DIR"/*; do
    cp -a "$file" "$OUT_DIR/"
done
shopt -u nullglob
rm -rf "$PRESERVE_DIR"

if [ "$LTO_MODE" = "thin" ]; then
    # The request is Full LTO.  The fallback job deliberately uses Thin LTO
    # when Full LTO exhausts the time/memory budget.
    sed 's/^CONFIG_LTO_CLANG_FULL=y/# CONFIG_LTO_CLANG_FULL is not set/' \
        "$FRAGMENT" > "$EFFECTIVE_FRAGMENT"
    printf 'CONFIG_LTO_CLANG_THIN=y\n' >> "$EFFECTIVE_FRAGMENT"
else
    cp "$FRAGMENT" "$EFFECTIVE_FRAGMENT"
fi

# Options whose existence depends on the BakaSU version (currently
# KSU_SUSFS_HAS_MAGIC_MOUNT / KSU_SUSFS_SUS_SU).  apply-ksu-susfs.sh writes
# only symbols that exist in the tree; absent options stay as comments.
if [ -f "$SUSFS_EXTRA" ]; then
    if grep -qE '^(CONFIG_[A-Za-z0-9_]+=|# CONFIG_[A-Za-z0-9_]+ is not set$)' "$SUSFS_EXTRA"; then
        printf '\n# --- version-specific SUSFS options ---\n' >> "$EFFECTIVE_FRAGMENT"
        grep -E '^(CONFIG_[A-Za-z0-9_]+=|# CONFIG_[A-Za-z0-9_]+ is not set$)' \
            "$SUSFS_EXTRA" >> "$EFFECTIVE_FRAGMENT"
    fi
fi

cp "$BUILD_FIXES" "$OUT_DIR/effective-build-fixes.fragment"

echo "==> merging $EFFECTIVE_FRAGMENT and $OUT_DIR/effective-build-fixes.fragment"
"$ROOT/scripts/kconfig/merge_config.sh" -m -O "$OUT_DIR" \
    "$OUT_DIR/.config" "$EFFECTIVE_FRAGMENT" \
    "$OUT_DIR/effective-build-fixes.fragment" 2>&1 | tee "$OUT_DIR/merge-config.log"

echo "==> olddefconfig"
make -C "$ROOT" O="$OUT_DIR" ARCH=arm64 LLVM=1 LLVM_IAS=1 \
    CC=clang olddefconfig 2>&1 | tee "$OUT_DIR/olddefconfig.log"

[ -s "$OUT_DIR/.config" ] || { echo "ERROR: olddefconfig produced no .config" >&2; exit 1; }
grep -qx '# CONFIG_TRIM_UNUSED_KSYMS is not set' "$OUT_DIR/.config" \
    || { echo "ERROR: build fix CONFIG_TRIM_UNUSED_KSYMS=n was not applied" >&2; exit 1; }
cp "$OUT_DIR/.config" "$OUT_DIR/final.config"

echo "==> auditing requested options"
python3 "$ROOT/scripts/check-config.py" \
    --fragment "$EFFECTIVE_FRAGMENT" \
    --config "$OUT_DIR/.config" \
    --lto "$LTO_MODE" \
    --out "$OUT_DIR/config-report.md" \
    | tee "$OUT_DIR/config-report.txt"

{
    echo ""
    echo "## Build fixes"
    echo ""
    echo "The extracted GSI config contains an absolute AOSP build-host path in"
    echo "\`CONFIG_UNUSED_KSYMS_WHITELIST\`.  \`configs/build-fixes.fragment\` disables"
    echo "\`CONFIG_TRIM_UNUSED_KSYMS\`, which both makes autoksyms build outside the"
    echo "AOSP build host and keeps exports available for out-of-tree/vendor modules."
} >> "$OUT_DIR/config-report.md"
{
    echo ""
    echo "BUILD FIX: CONFIG_TRIM_UNUSED_KSYMS is disabled because the extracted"
    echo "GSI config points CONFIG_UNUSED_KSYMS_WHITELIST at an AOSP build-host path."
} >> "$OUT_DIR/config-report.txt"

echo "==> KernelSU/SUSFS effective options"
grep -E '^(CONFIG_KSU|# CONFIG_KSU)' "$OUT_DIR/.config" | tee "$OUT_DIR/ksu-config.txt"
{
    echo ""
    echo "## KernelSU / SUSFS options after olddefconfig"
    echo ""
    echo '```'
    cat "$OUT_DIR/ksu-config.txt"
    echo '```'
} >> "$OUT_DIR/config-report.md"
{
    echo ""
    echo "KERNELSU/SUSFS OPTIONS AFTER OLDDEFCONFIG"
    cat "$OUT_DIR/ksu-config.txt"
} >> "$OUT_DIR/config-report.txt"

echo "==> final .config written to $OUT_DIR/.config"
