#!/usr/bin/env bash
#
# Package a built Image as:
#   - an AnyKernel3 flashable zip (Image only; DTB stays in vendor_boot)
#   - a boot.img repacked with magiskboot from the original boot.img
#   - configuration/module-compatibility reports
#   - the separate Zyomi16 tweaks module
#
# The repacked boot.img and the AnyKernel3 zip are not AVB-signed.  See
# docs/ROLLBACK.md for the fastboot flags needed to boot them on an unlocked
# device.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="${OUT_DIR:-$ROOT/out}"
LTO_MODE="${LTO_MODE:-full}"
KERNEL_RELEASE="${KERNEL_RELEASE:-$(cat "$OUT_DIR/kernel-release.txt" 2>/dev/null || true)}"
KERNEL_IMAGE="${KERNEL_IMAGE:-$OUT_DIR/arch/arm64/boot/Image}"
BOOT_IMAGE="${BOOT_IMAGE:-$ROOT/device-inputs/boot.img}"
ARTIFACT_DIR="${ARTIFACT_DIR:-$ROOT/artifacts}"
WORK_DIR="${WORK_DIR:-$ROOT/package-work}"
MAGISKBOOT="${MAGISKBOOT:-$ROOT/magiskboot}"
MAGISK_APK="${MAGISK_APK:-$ROOT/Magisk-v27.0.apk}"
MAGISK_APK_SHA256="${MAGISK_APK_SHA256:-f511bd33d3242911d05b0939f910a3133ef2ba0e0ff1e098128f9f3cd0c16610}"
ANYKERNEL3_COMMIT="${ANYKERNEL3_COMMIT:-41f04bdb4ee30a44e429c2c1131d5e8bb32b15f1}"
ANYKERNEL3_SHA256="${ANYKERNEL3_SHA256:-792b37fec7d1221570a4f1deb777a2d2cb8261596b1465a70bd7abfb30e268a2}"
RUN_NUMBER="${RUN_NUMBER:-local}"
GITHUB_SHA="${GITHUB_SHA:-unknown}"
PACKAGE_BOOT_IMG="${PACKAGE_BOOT_IMG:-true}"

[ -n "$KERNEL_RELEASE" ] || { echo "ERROR: KERNEL_RELEASE is empty" >&2; exit 1; }
[ -f "$KERNEL_IMAGE" ] || { echo "ERROR: missing Image $KERNEL_IMAGE" >&2; exit 1; }
[ -f "$OUT_DIR/.config" ] || { echo "ERROR: missing final .config" >&2; exit 1; }

BASE_NAME="Zyomi16-marble-${KERNEL_RELEASE}-${LTO_MODE}-r${RUN_NUMBER}"
mkdir -p "$ARTIFACT_DIR"
rm -rf "$WORK_DIR"
mkdir -p "$WORK_DIR"

# ---------------------------------------------------------------------------
# magiskboot (x86_64 host binary from the official Magisk APK)
# ---------------------------------------------------------------------------
if [ ! -x "$MAGISKBOOT" ]; then
    if [ ! -f "$MAGISK_APK" ]; then
        echo "==> downloading Magisk v27.0 APK"
        curl -fL --retry 3 -o "$MAGISK_APK" \
            https://github.com/topjohnwu/Magisk/releases/download/v27.0/Magisk-v27.0.apk
    fi
    echo "$MAGISK_APK_SHA256  $MAGISK_APK" | sha256sum -c -
    unzip -p "$MAGISK_APK" lib/x86_64/libmagiskboot.so > "$MAGISKBOOT"
    chmod +x "$MAGISKBOOT"
fi

# ---------------------------------------------------------------------------
# Repack the original boot.img with the new Image and the requested cmdline
# ---------------------------------------------------------------------------
if [ "$PACKAGE_BOOT_IMG" = "true" ]; then
    [ -f "$BOOT_IMAGE" ] || { echo "ERROR: missing $BOOT_IMAGE" >&2; exit 1; }
    BOOT_WORK="$WORK_DIR/boot-repack"
    mkdir -p "$BOOT_WORK"
    echo "==> unpacking original boot.img"
    (
        cd "$BOOT_WORK"
        "$MAGISKBOOT" unpack -h "$BOOT_IMAGE" > unpack.log 2>&1
    )

    cp "$KERNEL_IMAGE" "$BOOT_WORK/kernel"
    python3 - "$BOOT_WORK/header" <<'PY'
import sys
from pathlib import Path

path = Path(sys.argv[1])
requested = ["cgroup.memory=nokmem", "kasan=off", "audit=0"]
lines = path.read_text(errors="surrogateescape").splitlines(True)
found = False
for index, line in enumerate(lines):
    if line.startswith("cmdline="):
        value = line[len("cmdline="):].rstrip("\n")
        tokens = value.split()
        for wanted in requested:
            name = wanted.split("=", 1)[0]
            tokens = [t for t in tokens if t.split("=", 1)[0] != name]
            tokens.append(wanted)
        lines[index] = "cmdline=" + " ".join(tokens) + "\n"
        found = True
        break
if not found:
    lines.append("cmdline=" + " ".join(requested) + "\n")
path.write_text("".join(lines), errors="surrogateescape")
PY

    BOOT_OUT="$ARTIFACT_DIR/boot-${BASE_NAME}.img"
    echo "==> repacking boot.img"
    (
        cd "$BOOT_WORK"
        "$MAGISKBOOT" repack "$BOOT_IMAGE" "$BOOT_OUT" > repack.log 2>&1
    )

    echo "==> verifying repacked boot.img"
    VERIFY="$WORK_DIR/boot-verify"
    mkdir -p "$VERIFY"
    (
        cd "$VERIFY"
        "$MAGISKBOOT" unpack -h "$BOOT_OUT" > unpack.log 2>&1
        grep '^cmdline=' header
        cmp kernel "$KERNEL_IMAGE"
    )
    rm -rf "$VERIFY"
fi

# ---------------------------------------------------------------------------
# AnyKernel3 zip.  The marble DTB lives in vendor_boot, so no DTB is bundled.
# ---------------------------------------------------------------------------
echo "==> assembling AnyKernel3"
AK3="$WORK_DIR/anykernel3"
rm -rf "$AK3"
mkdir -p "$AK3"
curl -fL --retry 3 -o "$WORK_DIR/anykernel3.tar.gz" \
    "https://github.com/osm0sis/AnyKernel3/archive/${ANYKERNEL3_COMMIT}.tar.gz"
echo "$ANYKERNEL3_SHA256  $WORK_DIR/anykernel3.tar.gz" | sha256sum -c -
tar -xzf "$WORK_DIR/anykernel3.tar.gz" -C "$AK3" --strip-components=1
cp "$ROOT/anykernel3/anykernel.sh" "$AK3/anykernel.sh"
cp "$KERNEL_IMAGE" "$AK3/Image"
python3 - "$AK3/anykernel.sh" "$KERNEL_RELEASE" "$LTO_MODE" "$GITHUB_SHA" <<'PY'
import sys
from pathlib import Path

path = Path(sys.argv[1])
text = path.read_text()
replacements = {
    "@KERNEL_RELEASE@": sys.argv[2],
    "@LTO_MODE@": sys.argv[3],
    "@GIT_SHA@": sys.argv[4][:12],
}
for key, value in replacements.items():
    text = text.replace(key, value)
path.write_text(text)
PY

AK3_ZIP="$ARTIFACT_DIR/${BASE_NAME}.zip"
rm -f "$AK3_ZIP"
(
    cd "$AK3"
    zip -r -9 "$AK3_ZIP" . \
        -x '.github/*' 'README.md' > /dev/null
)

# ---------------------------------------------------------------------------
# Separate KernelSU/Magisk tweaks module (no tweaks are in the kernel config)
# ---------------------------------------------------------------------------
echo "==> assembling tweaks module"
TWEAKS="$WORK_DIR/tweaks"
cp -a "$ROOT/tweaks" "$TWEAKS"
find "$TWEAKS" -type f -name '*.sh' -exec chmod 0755 {} +
find "$TWEAKS" -type f ! -name '*.sh' -exec chmod 0644 {} +
TWEAKS_ZIP="$ARTIFACT_DIR/Zyomi16-Tweaks-v1.zip"
rm -f "$TWEAKS_ZIP"
(
    cd "$TWEAKS"
    zip -r -9 "$TWEAKS_ZIP" . > /dev/null
)

# ---------------------------------------------------------------------------
# Reports and checksums
# ---------------------------------------------------------------------------
cp "$KERNEL_IMAGE" "$ARTIFACT_DIR/Image-${BASE_NAME}"
cp "$OUT_DIR/.config" "$ARTIFACT_DIR/config-${BASE_NAME}.txt"
cp "$OUT_DIR/config-report.md" "$ARTIFACT_DIR/config-report-${BASE_NAME}.md"
[ -f "$OUT_DIR/config-report.txt" ] && cp "$OUT_DIR/config-report.txt" "$ARTIFACT_DIR/config-report-${BASE_NAME}.txt"
[ -f "$OUT_DIR/module-compat.md" ] && cp "$OUT_DIR/module-compat.md" "$ARTIFACT_DIR/module-compat-${BASE_NAME}.md"
[ -f "$OUT_DIR/module-compat.csv" ] && cp "$OUT_DIR/module-compat.csv" "$ARTIFACT_DIR/module-compat-${BASE_NAME}.csv"
[ -f "$OUT_DIR/merge-config.log" ] && cp "$OUT_DIR/merge-config.log" "$ARTIFACT_DIR/merge-config.log"
[ -f "$OUT_DIR/olddefconfig.log" ] && cp "$OUT_DIR/olddefconfig.log" "$ARTIFACT_DIR/olddefconfig.log"
[ -f "$ROOT/integration-info.txt" ] && cp "$ROOT/integration-info.txt" "$ARTIFACT_DIR/integration-info.txt"

cat > "$ARTIFACT_DIR/README.txt" <<EOF
Zyomi16 marble kernel build
===========================

Kernel release : ${KERNEL_RELEASE}
LTO mode       : ${LTO_MODE}
Git SHA        : ${GITHUB_SHA}
Workflow run   : ${RUN_NUMBER}

Artifacts
---------
${BASE_NAME}.zip
    AnyKernel3 flashable zip.  It writes Image to the active boot partition and
    keeps the existing boot ramdisk.  The marble DTB remains untouched in
    vendor_boot.

boot-${BASE_NAME}.img
    boot.img repacked with magiskboot from the original boot.img.  The boot
    header cmdline includes:
        cgroup.memory=nokmem kasan=off audit=0

Image-${BASE_NAME}
    Raw arm64 Image.

config-${BASE_NAME}.txt
    Final .config; config-report-...md lists requested options that Kconfig
    hid/changed.

Zyomi16-Tweaks-v1.zip
    Separate KernelSU/Magisk module with service.d scripts and sysctl values.
    It is not part of the kernel image.

IMPORTANT
---------
- Neither flashable image is AVB-signed.  Read docs/ROLLBACK.md before flashing.
- The vendor modules in the supplied vendor_boot/vendor_dlkm images are from
  another GKI build (normally 5.10.160-gki-gd28eeb36ae86).  They will not load
  into this 5.10 kernel because their vermagic differs.  A boot-only flash does
  not rebuild those modules; on a stock ROM this can prevent boot.
- This kernel was built from a GKI tree without the marble/sm7475 DTS.  Use the
  existing vendor_boot DTB; do not replace the DTB.
EOF

(
    cd "$ARTIFACT_DIR"
    find . -maxdepth 1 -type f ! -name SHA256SUMS -printf '%f\n' | sort | while IFS= read -r file; do
        sha256sum "$file"
    done > SHA256SUMS
)

ls -lh "$ARTIFACT_DIR"
echo "==> packaging complete: $ARTIFACT_DIR"
