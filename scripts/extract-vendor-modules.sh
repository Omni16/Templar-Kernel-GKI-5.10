#!/usr/bin/env bash
#
# Extract the vendor module trees from the original vendor_boot.img and
# vendor_dlkm_a.img so their vermagic and symbol CRCs can be compared with the
# newly built kernel.
#
# magiskboot unpacks the vendor_boot v4 header and leaves the vendor ramdisk as
# a compressed cpio.  The compression can be lz4, gzip or raw depending on the
# ROM; handle all three.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VENDOR_BOOT="${VENDOR_BOOT:-$ROOT/device-inputs/vendor_boot.img}"
VENDOR_DLKM="${VENDOR_DLKM:-$ROOT/device-inputs/vendor_dlkm_a.img}"
MAGISKBOOT="${MAGISKBOOT:-$ROOT/magiskboot}"
DEST="${DEST:-$ROOT/out/vendor-modules}"
WORK="${WORK:-$ROOT/out/vendor-extract}"

[ -f "$VENDOR_BOOT" ] || { echo "ERROR: missing $VENDOR_BOOT" >&2; exit 1; }
[ -f "$VENDOR_DLKM" ] || { echo "ERROR: missing $VENDOR_DLKM" >&2; exit 1; }
[ -x "$MAGISKBOOT" ] || { echo "ERROR: $MAGISKBOOT is not executable" >&2; exit 1; }

rm -rf "$DEST" "$WORK"
mkdir -p "$DEST" "$WORK/vendor_boot" "$DEST/vendor_dlkm-root"

echo "==> unpacking vendor_boot.img"
(
    cd "$WORK/vendor_boot"
    "$MAGISKBOOT" unpack "$VENDOR_BOOT" > unpack.log 2>&1
)

RAMDISK="$WORK/vendor_boot/ramdisk.cpio"
[ -f "$RAMDISK" ] || { echo "ERROR: magiskboot did not create ramdisk.cpio" >&2; exit 1; }

CPIO="$RAMDISK"
if file "$RAMDISK" | grep -qi 'lz4'; then
    echo "==> decompressing lz4 vendor ramdisk"
    lz4 -d -f "$RAMDISK" "$RAMDISK.raw" >/dev/null
    CPIO="$RAMDISK.raw"
elif file "$RAMDISK" | grep -qi 'gzip'; then
    echo "==> decompressing gzip vendor ramdisk"
    gzip -dc "$RAMDISK" > "$RAMDISK.raw"
    CPIO="$RAMDISK.raw"
elif file "$RAMDISK" | grep -qi 'xz'; then
    echo "==> decompressing xz vendor ramdisk"
    xz -dc "$RAMDISK" > "$RAMDISK.raw"
    CPIO="$RAMDISK.raw"
fi

echo "==> extracting vendor ramdisk"
mkdir -p "$DEST/vendor_boot-root"
(
    cd "$DEST/vendor_boot-root"
    cpio -idm --no-absolute-filenames --quiet < "$CPIO"
)

echo "==> extracting vendor_dlkm_a.img (EROFS)"
fsck.erofs --extract="$DEST/vendor_dlkm-root" "$VENDOR_DLKM"

BOOT_COUNT="$(find "$DEST/vendor_boot-root" -type f \( -name '*.ko' -o -name '*.ko.xz' -o -name '*.ko.zst' -o -name '*.ko.gz' -o -name '*.ko.lz4' \) | wc -l)"
DLKM_COUNT="$(find "$DEST/vendor_dlkm-root" -type f \( -name '*.ko' -o -name '*.ko.xz' -o -name '*.ko.zst' -o -name '*.ko.gz' -o -name '*.ko.lz4' \) | wc -l)"

echo "vendor_boot modules: $BOOT_COUNT"
echo "vendor_dlkm modules: $DLKM_COUNT"

[ "$BOOT_COUNT" -gt 0 ] || { echo "ERROR: no modules found in vendor_boot" >&2; exit 1; }
[ "$DLKM_COUNT" -gt 0 ] || { echo "ERROR: no modules found in vendor_dlkm" >&2; exit 1; }

printf '%s\n' "$DEST/vendor_boot-root" "$DEST/vendor_dlkm-root"
