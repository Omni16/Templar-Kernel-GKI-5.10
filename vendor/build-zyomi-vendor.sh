#!/usr/bin/env bash
# =============================================================================
# vendor/build-zyomi-vendor.sh — build kernel "vendor" cho marble (sm7475)
#
# Cây nguồn : Pzqqt/android_kernel_xiaomi_marble, nhánh bouquet_ci — superset của dòng
#             Melt (chứa melt-rebase + dts vendor + build-tools); pin qua KERNEL_SHA_EXPECT
# Config    : defconfig dòng Melt nhúng sẵn (vendor/marble-melt_defconfig, m4lg@3097a527:
#             touch MIUI GOODIX_BRL_9916 + XIAOMI_TOUCHFEATURE + module MIUI) + fragment
#             Droidspaces 22 config (gồm 2 option BREAK kABI) + LTO clang full + CFI
#             + ép CONFIG_BUILD_ARM64_DT_OVERLAY=y (melt thiếu, dts Makefile cần)
#             + LOCALVERSION=-${KERNEL_NAME} + env LOCALVERSION=-<BUILD_SHA>
# Root      : BakaSU (bake thẳng vào Image) + SUSFS (chỉ patch 50_add… như workflow GKI
#             đã kiểm chứng runtime; BakaSU/ReSukiSU có hook SUSFS sẵn trong kernel/)
# Đầu ra    : ${OUTPUT_DIR}/{Image, Image_vmlinux.symvers, modules/**, devicetree/**,
#             build-info.txt, modules-report.txt, build.log}
#
# QUY ĐỊNH DỰ ÁN: chỉ build trên GitHub Actions (workflow Zyomi-vendor.yml).
# =============================================================================
set -euo pipefail

log()  { echo -e "\n==> $*"; }
warn() { echo -e "[warn] $*"; }
die()  { echo -e "\n::error::$*" >&2; exit 1; }

# ---------- input ----------
: "${KERNEL_DIR:?KERNEL_DIR chưa được đặt (thư mục cây kernel)}"
: "${BAKASU_DIR:?BAKASU_DIR chưa được đặt (thư mục checkout BakaSU)}"
: "${SUSFS_DIR:?SUSFS_DIR chưa được đặt (thư mục checkout susfs4ksu)}"
: "${TOOLING_DIR:?TOOLING_DIR chưa được đặt (thư mục build-tools: avbtool, merge_dtbs.py, …)}"

KERNEL_NAME="${KERNEL_NAME:-Zyomi16}"
BUILD_SHA="${BUILD_SHA:-}"
if [ -z "$BUILD_SHA" ] && [ -n "${KERNEL_SHA_EXPECT:-}" ]; then
    BUILD_SHA="${KERNEL_SHA_EXPECT:0:12}"
fi
BUILD_SHA="${BUILD_SHA:-unknown}"
OUTPUT_DIR="${OUTPUT_DIR:-$HOME/zyomi_out}"
JOBS="${JOBS:-$(nproc)}"
VENDOR_DIR="${VENDOR_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
MODULES_DIR="${MODULES_DIR:-$VENDOR_DIR/modules}"
FRAGMENT="${FRAGMENT:-$VENDOR_DIR/droidspaces-vendor.fragment}"

[ -d "$KERNEL_DIR" ]  || die "KERNEL_DIR không tồn tại: $KERNEL_DIR"
[ -d "$BAKASU_DIR" ]  || die "BAKASU_DIR không tồn tại: $BAKASU_DIR"
[ -d "$SUSFS_DIR" ]   || die "SUSFS_DIR không tồn tại: $SUSFS_DIR"
[ -d "$TOOLING_DIR" ] || die "TOOLING_DIR không tồn tại: $TOOLING_DIR"
[ -f "$FRAGMENT" ]    || die "thiếu fragment: $FRAGMENT"
[ -f "$MODULES_DIR/both.txt" ] || die "thiếu baseline module: $MODULES_DIR/both.txt"

export PATH="$TOOLING_DIR:$PATH"
export LOCALVERSION="-${BUILD_SHA}"
export KBUILD_BUILD_HOST="${KBUILD_BUILD_HOST:-ubuntu}"
export KBUILD_BUILD_USER="${KBUILD_BUILD_USER:-github}"

mkdir -p "$OUTPUT_DIR"

# ---------- 0) sanity ----------
log "0/8 Kiểm tra đầu vào"
command -v clang >/dev/null || die "không thấy clang trong PATH (toolchain chưa setup?)"
command -v llvm-strip >/dev/null || die "không thấy llvm-strip trong PATH"
for f in avbtool fdtget fdtput mkdtboimg.py merge_dtbs.py; do
    command -v "$f" >/dev/null || die "thiếu build-tool '$f' (TOOLING_DIR=$TOOLING_DIR)"
done
echo "[i] clang: $(clang --version | head -1)"
echo "[i] LOCALVERSION env: $LOCALVERSION (nối sau CONFIG_LOCALVERSION)"

cd "$KERNEL_DIR"
[ -f arch/arm64/configs/marble_defconfig ] || die "không phải cây marble: thiếu arch/arm64/configs/marble_defconfig"
[ -d techpack ] || die "cây nguồn thiếu techpack/ — sai cây?"
[ -d arch/arm64/boot/dts/vendor/qcom ] || die "cây nguồn thiếu arch/arm64/boot/dts/vendor/qcom — cần nhánh bouquet_ci (dòng Melt thuần không có dts vendor)"
DEFCONFIG_PATH="arch/arm64/configs/marble_defconfig"

if [ -n "${KERNEL_SHA_EXPECT:-}" ]; then
    ACTUAL_SHA=$(git rev-parse HEAD)
    [ "$ACTUAL_SHA" = "$KERNEL_SHA_EXPECT" ] || die "cây kernel lệch pin: HEAD=$ACTUAL_SHA, mong đợi=$KERNEL_SHA_EXPECT"
    echo "[i] Kernel tree pin OK: $ACTUAL_SHA"
else
    warn "KERNEL_SHA_EXPECT trống — bỏ qua kiểm tra pin cây nguồn"
fi

MAKE_ARGS=(ARCH=arm64 LLVM=1 LLVM_IAS=1 O=out)
KCFLAGS_STR="-D__ANDROID_COMMON_KERNEL__ -O3"
KBUILD_LDFLAGS_STR="-O3 --lto-O3"

# ---------- 1) BakaSU ----------
log "1/8 Tích hợp BakaSU (bake vào Image)"
[ -f "$BAKASU_DIR/kernel/Kconfig" ] || die "BAKASU_DIR thiếu kernel/Kconfig — chắc chắn là repo BakaSU?"
grep -qE '^config KSU_SUSFS$' "$BAKASU_DIR/kernel/Kconfig" || die "BakaSU thiếu config KSU_SUSFS — không build được SUSFS"
rm -rf drivers/kernelsu
mkdir -p drivers/kernelsu
cp -r "$BAKASU_DIR/kernel" drivers/kernelsu/kernel
if [ -d "$BAKASU_DIR/uapi" ]; then
    cp -r "$BAKASU_DIR/uapi" drivers/kernelsu/uapi
fi
if [ -d "$BAKASU_DIR/.git" ]; then
    ln -sfn "$BAKASU_DIR/.git" drivers/kernelsu/.git   # cho Kbuild đọc version
fi

if ! grep -q 'drivers/kernelsu/kernel/Kconfig' drivers/Kconfig; then
    sed -i '/drivers\/most\/Kconfig/asource "drivers\/kernelsu\/kernel\/Kconfig"' drivers/Kconfig || true
fi
if ! grep -q 'drivers/kernelsu/kernel/Kconfig' drivers/Kconfig; then
    echo 'source "drivers/kernelsu/kernel/Kconfig"' >> drivers/Kconfig
fi
grep -q 'drivers/kernelsu/kernel/Kconfig' drivers/Kconfig || die "chưa chèn được source Kconfig của kernelsu"

grep -q 'kernelsu/kernel/' drivers/Makefile || echo 'obj-y += kernelsu/kernel/' >> drivers/Makefile
grep -q 'kernelsu/kernel/' drivers/Makefile || die "chưa thêm được dòng kernelsu vào drivers/Makefile"

echo "[i] BakaSU: $(git -C "$BAKASU_DIR" rev-parse --short HEAD 2>/dev/null || echo '???')"

# ---------- 2) SUSFS ----------
log "2/8 Tích hợp SUSFS (chỉ 50_add — BakaSU đã có hook sẵn)"
PATCH_FILE="$SUSFS_DIR/kernel_patches/50_add_susfs_in_gki-android12-5.10.patch"
[ -d "$SUSFS_DIR/kernel_patches/fs" ] || die "SUSFS_DIR thiếu kernel_patches/fs"
[ -f "$PATCH_FILE" ] || die "thiếu patch: $PATCH_FILE"
cp -f "$SUSFS_DIR"/kernel_patches/fs/* fs/
cp -f "$SUSFS_DIR"/kernel_patches/include/linux/* include/linux/
git apply --check "$PATCH_FILE" || die "patch 50_add không áp được sạch trên cây này (pin cây/susfs lệch?)"
git apply "$PATCH_FILE"
[ -f fs/susfs.c ] || die "susfs.c chưa vào cây sau khi patch"
echo "[i] SUSFS: $(git -C "$SUSFS_DIR" rev-parse --short HEAD 2>/dev/null || echo '???')"

# ---------- 2b) Vá driver goodix (bắt buộc cho LTO FULL) ----------
log "2b/8 Vá goodix_ts_core.c (container_of gesture_work — type mismatch làm link LTO full fail)"
GOODIX_FIX="$VENDOR_DIR/patches/goodix-9916r-fix-gesture-container-of.patch"
[ -f "$GOODIX_FIX" ] || die "thiếu patch vá goodix: $GOODIX_FIX"
GOODIX_SRC="drivers/input/touchscreen/goodix_9916r/goodix_ts_core.c"
# Variant MIUI (CONFIG_TOUCHSCREEN_XIAOMI_TOUCHFEATURE): container_of(work, …) trỏ vào member
# 'gesture_work' kiểu delayed_work -> check container_of() của kernel bung thành ld.lld
# "dontcall-error: pointer type mismatch in container_of()" khi clang codegen LTO FULL cho
# module goodix_core (run 39216833751). Sửa đúng theo pattern bản LOS trong cùng file
# (to_delayed_work) — runtime không đổi vì work_struct là member đầu của delayed_work.
git apply --check "$GOODIX_FIX" || die "patch vá goodix không áp được sạch (cây lệch pin?)"
git apply "$GOODIX_FIX"
grep -q 'container_of(dwork, struct goodix_ts_core, gesture_work);' "$GOODIX_SRC" \
    || die "vá goodix chưa hiệu lực (không thấy container_of(dwork, …))"
if grep -q 'container_of(work, struct goodix_ts_core, gesture_work);' "$GOODIX_SRC"; then
    die "vá goodix chưa hiệu lực (vẫn còn container_of(work, …))"
fi

# ---------- 3) defconfig edits ----------
log "3/8 Nạp defconfig Melt + sửa (LOCALVERSION, LTO full, DT_OVERLAY)"
MELT_DEFCONFIG="$VENDOR_DIR/marble-melt_defconfig"
[ -s "$MELT_DEFCONFIG" ] || die "thiếu $MELT_DEFCONFIG (defconfig dòng Melt để nhúng)"
# Provenance: đúng bản Melt (m4lg@3097a527) — 2 marker đặc trưng dòng Melt:
# touch MIUI (9916) + kshrink lruvecd. Đây là lý do chọn defconfig Melt thay vì
# defconfig Bouquet (touch LOS + cpq sched).
grep -q '^CONFIG_TOUCHSCREEN_GOODIX_BRL_9916=m$' "$MELT_DEFCONFIG" || die "marble-melt_defconfig không đúng bản Melt (thiếu GOODIX_BRL_9916)"
grep -q '^CONFIG_KSHRINK_LRUVECD=m$' "$MELT_DEFCONFIG" || die "marble-melt_defconfig không đúng bản Melt (thiếu KSHRINK_LRUVECD)"
cp -f "$MELT_DEFCONFIG" "$DEFCONFIG_PATH"
echo "[i] Đã nạp defconfig Melt (m4lg@3097a527) làm $DEFCONFIG_PATH"

if grep -qE '^CONFIG_LOCALVERSION=' "$DEFCONFIG_PATH"; then
    sed -i "s|^CONFIG_LOCALVERSION=.*|CONFIG_LOCALVERSION=\"-${KERNEL_NAME}\"|" "$DEFCONFIG_PATH"
else
    echo "CONFIG_LOCALVERSION=\"-${KERNEL_NAME}\"" >> "$DEFCONFIG_PATH"
fi
if grep -qE '^CONFIG_LOCALVERSION_AUTO' "$DEFCONFIG_PATH"; then
    sed -i 's|^CONFIG_LOCALVERSION_AUTO=.*|# CONFIG_LOCALVERSION_AUTO is not set|' "$DEFCONFIG_PATH"
fi
grep -q '^# CONFIG_LOCALVERSION_AUTO is not set' "$DEFCONFIG_PATH" || \
    echo '# CONFIG_LOCALVERSION_AUTO is not set' >> "$DEFCONFIG_PATH"

if ! grep -q '^CONFIG_LTO_CLANG_FULL=y' "$DEFCONFIG_PATH"; then
    sed -i 's|^CONFIG_LTO_CLANG_THIN=y$|# CONFIG_LTO_CLANG_THIN is not set|' "$DEFCONFIG_PATH"
    sed -i 's|^# CONFIG_LTO_CLANG_FULL is not set$|CONFIG_LTO_CLANG_FULL=y|' "$DEFCONFIG_PATH"
    grep -q '^CONFIG_LTO_CLANG_FULL=y' "$DEFCONFIG_PATH" || echo 'CONFIG_LTO_CLANG_FULL=y' >> "$DEFCONFIG_PATH"
fi
grep -q '^CONFIG_LTO_CLANG_FULL=y' "$DEFCONFIG_PATH" || die "chưa bật được LTO full trong defconfig"

# BUILD_ARM64_DT_OVERLAY: bản Melt thiếu (bản Bouquet có) nhưng arch/arm64/boot/dts/vendor/qcom/
# Makefile bọc TOÀN BỘ dtb/dtbo vendor trong ifeq ($(CONFIG_BUILD_ARM64_DT_OVERLAY),y)
# -> thiếu là không sinh được ukee.dtb + overlay.dtbo cho vendor_boot.
if ! grep -q '^CONFIG_BUILD_ARM64_DT_OVERLAY=y$' "$DEFCONFIG_PATH"; then
    sed -i '/^CONFIG_BUILD_ARM64_DT_OVERLAY=/d' "$DEFCONFIG_PATH"
    echo 'CONFIG_BUILD_ARM64_DT_OVERLAY=y' >> "$DEFCONFIG_PATH"
fi
grep -q '^CONFIG_BUILD_ARM64_DT_OVERLAY=y$' "$DEFCONFIG_PATH" || die "chưa bật được BUILD_ARM64_DT_OVERLAY trong defconfig"
grep -E '^CONFIG_LTO|^CONFIG_LOCALVERSION|^CONFIG_BUILD_ARM64_DT_OVERLAY' "$DEFCONFIG_PATH" | sed 's/^/[i] defconfig: /'

# ---------- 4) build sạch + defconfig ----------
log "4/8 mrproper + marble_defconfig"
make "${MAKE_ARGS[@]}" mrproper
make "${MAKE_ARGS[@]}" marble_defconfig

# ---------- 5) fragment + KSU/SUSFS configs ----------
log "5/8 Áp fragment Droidspaces vendor (22 config) + config KSU/SUSFS"
N_FRAG=0
while IFS= read -r line; do
    key="${line%%=*}"
    ./scripts/config --file out/.config --enable "${key#CONFIG_}"
    N_FRAG=$((N_FRAG + 1))
done < <(grep -E '^CONFIG_[A-Za-z0-9_]+=y$' "$FRAGMENT")
[ "$N_FRAG" -eq 22 ] || die "fragment lạ: đọc được $N_FRAG dòng CONFIG_*=y (mong đợi 22)"

# CGROUP_SCHED/FAIR_GROUP_SCHED: dependency cho CFS_BANDWIDTH (bật tường minh cho chắc)
for opt in CGROUP_SCHED FAIR_GROUP_SCHED \
           KSU KSU_MULTI_MANAGER_SUPPORT \
           KSU_SUSFS KSU_SUSFS_SUS_PATH KSU_SUSFS_SUS_MOUNT KSU_SUSFS_SUS_KSTAT KSU_SUSFS_SUS_MAP \
           KSU_SUSFS_SPOOF_UNAME KSU_SUSFS_ENABLE_LOG KSU_SUSFS_OPEN_REDIRECT \
           KSU_SUSFS_HIDE_KSU_SUSFS_SYMBOLS KSU_SUSFS_SPOOF_CMDLINE_OR_BOOTCONFIG; do
    ./scripts/config --file out/.config --enable "$opt"
done
# UNAME_OVERRIDE xung đột KSU_SUSFS_SPOOF_UNAME — tắt (đúng build_bouquet.sh dòng 141-145)
./scripts/config --file out/.config --disable UNAME_OVERRIDE

make "${MAKE_ARGS[@]}" olddefconfig

# ---------- 6) verify out/.config ----------
log "6/8 Verify out/.config (mọi tính năng ghi trên tên zip phải được chứng minh)"
verify_y() { grep -qE "^CONFIG_$1=y$" out/.config || die "out/.config thiếu CONFIG_$1=y"; }
verify_n() { if grep -qE "^CONFIG_$1=y$" out/.config; then die "out/.config có CONFIG_$1=y nhưng không được phép"; fi; }

verify_y LTO_CLANG_FULL
# LTO_CLANG là bool ẩn (arch/Kconfig) được LTO_CLANG_FULL *select* -> kconfig ghi
# CONFIG_LTO_CLANG=y vào .config khi rev_dep active (đối chiếu scripts/kconfig/symbol.c).
# Vậy FULL=y kèm LTO_CLANG=y là trạng thái ĐÚNG, không phải lỗi.
verify_y LTO_CLANG
verify_n LTO_CLANG_THIN
verify_n LTO_NONE
verify_y CFI_CLANG
verify_y MODVERSIONS
verify_y KSU
verify_y KSU_MULTI_MANAGER_SUPPORT
verify_y KSU_SUSFS
verify_y CGROUP_SCHED
verify_y FAIR_GROUP_SCHED
verify_y CFS_BANDWIDTH
verify_y CGROUP_PIDS
verify_y BUILD_ARM64_DT_OVERLAY
verify_n UNAME_OVERRIDE
grep -q "^CONFIG_LOCALVERSION=\"-${KERNEL_NAME}\"" out/.config || die "CONFIG_LOCALVERSION trong out/.config không phải \"-${KERNEL_NAME}\""

N_OK=0
while IFS= read -r line; do
    key="${line%%=*}"
    grep -qE "^${key}=y$" out/.config || die "Kconfig đã bỏ ${key} sau olddefconfig (thiếu dependency?)"
    N_OK=$((N_OK + 1))
done < <(grep -E '^CONFIG_[A-Za-z0-9_]+=y$' "$FRAGMENT")
[ "$N_OK" -eq 22 ] || die "chỉ còn $N_OK/22 config Droidspaces"
echo "[i] Đủ 22/22 config Droidspaces (gồm CFS_BANDWIDTH + CGROUP_PIDS)"
grep -E '^CONFIG_(LTO_CLANG|CFI_CLANG|MODVERSIONS|KSU|KSU_SUSFS|KSU_MULTI_MANAGER_SUPPORT|CFS_BANDWIDTH|CGROUP_PIDS|BUILD_ARM64_DT_OVERLAY|LOCALVERSION)=' out/.config | sed 's/^/    /'

# ---------- 7) build ----------
log "7/8 Build kernel + modules (LTO full, -j${JOBS}) — log: $OUTPUT_DIR/build.log"
rm -rf out/arch/arm64/boot/dts/vendor/qcom   # ép build lại dtbs (theo build_bouquet.sh)
if ! make "${MAKE_ARGS[@]}" KCFLAGS="$KCFLAGS_STR" KBUILD_LDFLAGS="$KBUILD_LDFLAGS_STR" -j"$JOBS" 2>&1 | tee "$OUTPUT_DIR/build.log"; then
    die "make thất bại — xem $OUTPUT_DIR/build.log"
fi

DTS_OUT="out/arch/arm64/boot/dts/vendor/qcom"
if [ ! -d "$DTS_OUT" ]; then
    warn "chưa thấy $DTS_OUT sau build mặc định — chạy thêm 'make dtbs'"
    if ! make "${MAKE_ARGS[@]}" KCFLAGS="$KCFLAGS_STR" KBUILD_LDFLAGS="$KBUILD_LDFLAGS_STR" dtbs 2>&1 | tee -a "$OUTPUT_DIR/build.log"; then
        die "make dtbs thất bại"
    fi
fi

IMAGE=out/arch/arm64/boot/Image
[ -f "$IMAGE" ] || die "không thấy Image: $IMAGE"
[ -f out/vmlinux.symvers ] || die "không thấy out/vmlinux.symvers"
cp -f "$IMAGE" "$OUTPUT_DIR/Image"
cp -f out/vmlinux.symvers "$OUTPUT_DIR/Image_vmlinux.symvers"

# ---------- 8) modules + devicetree ----------
log "8/8 Gom modules + devicetree"
python3 "$VENDOR_DIR/gen-module-dirs.py" \
    --out "$PWD/out" \
    --lists "$MODULES_DIR" \
    --dest "$OUTPUT_DIR/modules" \
    --strip "$(command -v llvm-strip)" \
    --report "$OUTPUT_DIR/modules-report.txt" || die "gen-module-dirs.py thất bại"

# dtb merge — đúng build_bouquet.sh dòng 594-622
[ -f "$DTS_OUT/ukee.dtb" ] || die "thiếu $DTS_OUT/ukee.dtb"
[ -f "$DTS_OUT/marble-sm7475-pm8008-overlay.dtbo" ] || die "thiếu marble overlay dtbo"
DT_BASE="$OUTPUT_DIR/devicetree-base"
DT_TECH="$OUTPUT_DIR/devicetree-techpack"
DT_OUT="$OUTPUT_DIR/devicetree"
rm -rf "$DT_BASE" "$DT_TECH" "$DT_OUT"
mkdir -p "$DT_BASE" "$DT_TECH" "$DT_OUT"
cp "$DTS_OUT/ukee.dtb" "$DT_BASE/"
cp "$DTS_OUT/marble-sm7475-pm8008-overlay.dtbo" "$DT_BASE/"
for d in audio camera cvp display/display eva mmrm video; do
    mkdir -p "$DT_TECH/$(basename "$d")"
    cp "$DTS_OUT/$d"/*.dtbo "$DT_TECH/$(basename "$d")/" || die "thiếu dtbo techpack: $d"
done
merge_dtbs.py -b "$DT_BASE" -t "$DT_TECH" -o "$DT_OUT" || die "merge_dtbs.py thất bại"
mkdtboimg.py create "$DT_OUT/dtbo.img" "$DT_OUT/marble-sm7475-pm8008-overlay.dtbo" || die "mkdtboimg.py thất bại"
avbtool add_hash_footer --partition_name dtbo --partition_size $((24 * 1024 * 1024)) --image "$DT_OUT/dtbo.img" || die "avbtool thất bại"
rm -rf "$DT_BASE" "$DT_TECH"

# ---------- build info ----------
{
    echo "kernel_name : $KERNEL_NAME"
    echo "tree_sha    : $(git rev-parse HEAD)"
    echo "build_sha   : $BUILD_SHA"
    echo "date_utc    : $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "uts_release : $(strings "$IMAGE" | grep -m1 -oE 'Linux version [^ ]+' || true)"
    echo "compiler    : $(clang --version | head -1)"
    echo "--- out/.config (claims) ---"
    grep -E '^CONFIG_(LTO_CLANG|CFI_CLANG|MODVERSIONS|KSU|KSU_SUSFS|KSU_MULTI_MANAGER_SUPPORT|CFS_BANDWIDTH|CGROUP_PIDS|BUILD_ARM64_DT_OVERLAY|LOCALVERSION)=' out/.config || true
    echo "--- số mục trong module dirs (gồm cả file load/blocklist) ---"
    echo "vendor_boot_modules: $(find "$OUTPUT_DIR/modules/vendor_boot_modules" -type f | wc -l)"
    echo "vendor_dlkm_modules: $(find "$OUTPUT_DIR/modules/vendor_dlkm_modules" -type f | wc -l)"
    echo "--- devicetree ---"
    ls -la "$DT_OUT"/ | tail -n +2
} | tee "$OUTPUT_DIR/build-info.txt"

log "HOÀN TẤT — đầu ra tại $OUTPUT_DIR"
ls -la "$OUTPUT_DIR" "$OUTPUT_DIR/modules" | sed 's/^/    /'
