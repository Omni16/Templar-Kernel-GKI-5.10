#!/usr/bin/env bash
# =============================================================================
# package-ak3.sh — Ghep kernel Image + AnyKernel3 thanh zip flash duoc
#
# Dung ra:
#   <ten>.zip          zip flash duoc (chua Image + anykernel.sh + META-INF)
#   <ten>.zip.sha256   checksum
#   <ten>.txt          thong tin phien ban (kernel version / root / SUSFS / ...)
#
# Dung:
#   scripts/package-ak3.sh \
#     --image  out/arch/arm64/boot/Image \
#     --ak3    anykernel3 \
#     --config out/.config \
#     --root   ReSukiSU \
#     --susfs  on \
#     --version 5.10.269 --branch Templar-LinuxStable --commit abc1234 \
#     --label  "ReSukiSU+SUSFS+MultiMgr+Droidspace" \
#     --name   Zyomi16-5.10.269-Templar-LinuxStable-ReSukiSU-20261010_0827 \
#     --ak3-variant gki \
#     --kernel-name Zyomi16
#
# --kernel-name: ten kernel hien thi khi flash (kernel.string + banner + thu muc
#   backup). Mac dinh "Zyomi16". Chi giu A-Z a-z 0-9 . _ -, tu dong chuan hoa.
#
# Ma loi (de CI/doc phan loai):
#   2  sai cu phap
#   10 khong co Image
#   11 Image qua nho bat thuong
#   12 chon root nhung CONFIG_KSU chua =y
#   13 bat SUSFS nhung CONFIG_KSU_SUSFS chua =y
#   14 thu muc AK3 khong hop le (thieu anykernel.sh)
#   15 zip sau khi goi thieu file bat buoc
#   16 bat Multi Manager nhung CONFIG_KSU_MULTI_MANAGER_SUPPORT chua =y
#   17 co config (KSU/SUSFS/MULTI_MANAGER) trong .config nhung khong thuoc
#      lua chon hien tai — zip khong khop lua chon
#
# --warning "<cau canh bao>"  — truyen nhieu lan, in vao file .txt manifest
#   (vi du: canh bao SUSFS + Droidspaces, bo qua multi manager, ...)
#
# Ghi chu: AK3_MIN_IMAGE_MB cho phep ha nguong khi test du lieu gia
#   (mac dinh 8MB — kernel GKI that thuong 15..50MB)
# =============================================================================
set -euo pipefail

die() {
    local code="$1"; shift
    echo ""
    echo "::error::[LOI ${code}] $*"
    echo "[LOI ${code}] $*" >&2
    exit "$code"
}

usage() {
    awk 'NR>1 && /^set -euo/{exit} NR>1{sub(/^# ?/,"");print}' "$0"
}

IMAGE="" AK3_DIR="" CONFIG="" ROOT="none" SUSFS="off"
VERSION="" BRANCH="" COMMIT="" LABEL="" NAME=""
AK3_VARIANT="template" MM="unknown" DROID="unknown"
MIN_MB="${AK3_MIN_IMAGE_MB:-8}"
OUT_DIR="."
KNAME=""
WARNINGS=()

while [ $# -gt 0 ]; do
    case "$1" in
        --image)         IMAGE="$2";        shift 2 ;;
        --ak3)           AK3_DIR="$2";      shift 2 ;;
        --config)        CONFIG="$2";       shift 2 ;;
        --root)          ROOT="$2";         shift 2 ;;
        --susfs)         SUSFS="$2";        shift 2 ;;
        --version)       VERSION="$2";      shift 2 ;;
        --branch)        BRANCH="$2";       shift 2 ;;
        --commit)        COMMIT="$2";       shift 2 ;;
        --label)         LABEL="$2";        shift 2 ;;
        --name)          NAME="$2";         shift 2 ;;
        --kernel-name)   KNAME="$2";        shift 2 ;;
        --warning)       WARNINGS+=("$2");  shift 2 ;;
        --out)           OUT_DIR="$2";      shift 2 ;;
        --ak3-variant)   AK3_VARIANT="$2";  shift 2 ;;
        --multi-manager) MM="$2";           shift 2 ;;
        --droidspace)    DROID="$2";        shift 2 ;;
        --min-image-mb)  MIN_MB="$2";       shift 2 ;;
        -h|--help)       usage; exit 0 ;;
        *)               usage >&2; die 2 "tham so khong ro: $1" ;;
    esac
done

[ -n "$IMAGE" ] || die 2 "thieu --image"
[ -n "$AK3_DIR" ] || die 2 "thieu --ak3"
[ -n "$NAME" ] || die 2 "thieu --name"
# Ten file zip phai la ten FILE, khong duoc tro thanh duong dan. Neu NAME chua
# '/' (vi du ten nhanh ci-fix/ui-inputs duoc dua nguyen vao ten zip) thi
# ${OUT_DIR}/${NAME}.zip tro thanh duong dan thu muc khong ton tai, va loi xuat
# hien RAT XA o buoc `zip` voi chi so ra thi 15 — rat kho hieu. Kiem tra som tai day.
case "$NAME" in
    */*) die 2 "ten zip ('--name') khong duoc chua '/': '${NAME}' — phai chuyen '/' thanh '-' o buoc goi (vi du ci-fix-ui-inputs)" ;;
esac

# --- 1) khong co Image -------------------------------------------------------
[ -f "$IMAGE" ] || die 10 "khong tim thay kernel Image: ${IMAGE} (build that bai hoac chua chay buoc Build Kernel Image)"

# --- 2) Image qua nho bat thuong --------------------------------------------
img_size=$(stat -c%s "$IMAGE")
min_bytes=$(( MIN_MB * 1048576 ))
if [ "$img_size" -lt "$min_bytes" ]; then
    die 11 "Image qua nho bat thuong: $(( img_size / 1048576 ))MB < nguong ${MIN_MB}MB (${IMAGE}) — nghi build that bai, dung flash"
fi

# --- 14) AK3 hop le ----------------------------------------------------------
[ -d "$AK3_DIR" ] || die 14 "khong tim thay thu muc AK3: ${AK3_DIR}"
[ -f "$AK3_DIR/anykernel.sh" ] || die 14 "AK3 thieu anykernel.sh: ${AK3_DIR}"

# --- 12/13/16/17) kiem tra CONFIG khop dung lua chon ---------------------------
# Kiem tra CA 2 CHIEU (khong chi "chon nhung thieu"):
#   chon ma thieu  -> loi 12/13/16 (zip se khong co tinh nang da hua)
#   khong chon ma co -> loi 17 (tinh nang la do build truoc de lai -> sai lua chon)
ROOT_LC=$(printf '%s' "$ROOT" | tr '[:upper:]' '[:lower:]')
SUSFS_LC=$(printf '%s' "$SUSFS" | tr '[:upper:]' '[:lower:]')
MM_LC=$(printf '%s' "$MM" | tr '[:upper:]' '[:lower:]')

# chuan hoa: on|true|yes|1 = bat ; off|false|no|0 = tat ; con lai = khong xac dinh (bo qua)
want_on() { case "$1" in on|true|yes|1) echo 1 ;; off|false|no|0) echo 0 ;; *) echo -1 ;; esac; }
SUSFS_WANT=$(want_on "$SUSFS_LC")
MM_WANT=$(want_on "$MM_LC")

cfg_on() {   # $1 = ten config (da gom CONFIG_)
    [ -n "$CONFIG" ] && [ -f "$CONFIG" ] && grep -qE "^$1=y" "$CONFIG"
}
have_cfg() { [ -n "$CONFIG" ] && [ -f "$CONFIG" ]; }

if have_cfg; then
    # --- chon ma thieu ---
    if [ "$ROOT_LC" != "none" ]; then
        cfg_on CONFIG_KSU || die 12 "ban chon root='${ROOT}' nhung CONFIG_KSU khong phai =y trong ${CONFIG} — dung flash (se khong co root)"
    fi
    if [ "$SUSFS_WANT" = "1" ]; then
        cfg_on CONFIG_KSU_SUSFS || die 13 "ban bat SUSFS nhung CONFIG_KSU_SUSFS khong phai =y trong ${CONFIG} — dung flash (se khong co SUSFS)"
    fi
    if [ "$MM_WANT" = "1" ]; then
        cfg_on CONFIG_KSU_MULTI_MANAGER_SUPPORT || die 16 "ban bat Multi Manager nhung CONFIG_KSU_MULTI_MANAGER_SUPPORT khong phai =y trong ${CONFIG} — dung flash (manager se khong ket noi duoc)"
    fi

    # --- khong chon ma la co (config du tu build truoc, khong phai lua chon nay) ---
    MISMATCH=""
    if [ "$ROOT_LC" = "none" ] && cfg_on CONFIG_KSU; then
        MISMATCH="${MISMATCH} CONFIG_KSU"
    fi
    if [ "$SUSFS_WANT" != "1" ] && cfg_on CONFIG_KSU_SUSFS; then
        MISMATCH="${MISMATCH} CONFIG_KSU_SUSFS"
    fi
    if [ "$MM_WANT" != "1" ] && cfg_on CONFIG_KSU_MULTI_MANAGER_SUPPORT; then
        MISMATCH="${MISMATCH} CONFIG_KSU_MULTI_MANAGER_SUPPORT"
    fi
    if [ -n "$MISMATCH" ]; then
        die 17 "out/.config co config khong thuoc lua chon hien tai:${MISMATCH} — zip nay khong khop lua chon, dung flash"
    fi
fi

# --- chon ban AK3 nao dung trong zip ----------------------------------------
STAGE_SRC="$AK3_DIR"
case "$AK3_VARIANT" in
    template) ;;
    gki)      [ -f "ak3/anykernel-gki.sh" ]    || die 14 "thieu ak3/anykernel-gki.sh";    STAGE_SRC="AK3+GKI" ;;
    nongki)   [ -f "ak3/anykernel-nongki.sh" ] || die 14 "thieu ak3/anykernel-nongki.sh"; STAGE_SRC="AK3+NOGKI" ;;
    *)        die 2 "--ak3-variant phai la template|gki|nongki (nhan: ${AK3_VARIANT})" ;;
esac

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
STAGE="$WORK/stage"
cp -a "$AK3_DIR/." "$STAGE/"
rm -rf "$STAGE/.git" "$STAGE/.github"

if [ "$STAGE_SRC" != "$AK3_DIR" ]; then
    if [ "$STAGE_SRC" = "AK3+GKI" ]; then
        cp -f ak3/anykernel-gki.sh "$STAGE/anykernel.sh"
    else
        cp -f ak3/anykernel-nongki.sh "$STAGE/anykernel.sh"
    fi
    echo "[i] Dung ban AK3: ${AK3_VARIANT}"
fi

# --- dat Image vao zip (ten phai nam trong danh sach AK3 biet doc) -----------
case "$(basename "$IMAGE")" in
    zImage|zImage-dtb|Image|Image-dtb|Image.gz|Image.gz-dtb|Image.bz2|Image.bz2-dtb|\
    Image.lzo|Image.lzo-dtb|Image.lzma|Image.lzma-dtb|Image.xz|Image.xz-dtb|\
    Image.lz4|Image.lz4-dtb|Image.fit)
        img_name="$(basename "$IMAGE")" ;;
    *)
        echo "[i] $(basename "$IMAGE") khong phai ten AK3 quen thuoc — chuyen thanh 'Image'"
        img_name="Image" ;;
esac
cp -f "$IMAGE" "$STAGE/$img_name"

# --- variant.prop + branding -------------------------------------------------
DATE_TAG=$(date +'%Y%m%d_%H%M')
[ -n "$LABEL" ] || LABEL="$ROOT"
[ -n "$VERSION" ] || VERSION="unknown"
[ -n "$BRANCH" ] || BRANCH="unknown"

# --- ten kernel tuy chon (--kernel-name) -------------------------------------
# Chi phep chu, so, dau . _ - (danh sach file zip va ten artifact khong chiu
# ky tu dac biet). De trong/tu dong sua ve "Zyomi16".
KNAME_RAW="${KNAME}"
KNAME=$(printf '%s' "${KNAME:-Zyomi16}" | tr -c 'A-Za-z0-9._-' '-' \
        | sed -e 's/-\{2,\}/-/g' -e 's/^-//' -e 's/-$//')
[ -n "$KNAME" ] || KNAME="Zyomi16"
if [ -n "$KNAME_RAW" ] && [ "$KNAME" != "$KNAME_RAW" ]; then
    echo "[i] Ten kernel '${KNAME_RAW}' duoc chuan hoa thanh '${KNAME}' (chi giu A-Z a-z 0-9 . _ -)"
fi

{
    echo "KERNEL_NAME=${KNAME}"
    echo "VARIANT=${LABEL}"
    echo "KERNEL_VERSION=${VERSION}"
    echo "BRANCH=${BRANCH}"
    echo "COMMIT=${COMMIT}"
    echo "BUILD_DATE=${DATE_TAG}"
} > "$STAGE/variant.prop"

# Doi ten kernel trong AK3:
#   1) kernel.string  — dong ten hien thi len recovery khi flash
#   2) KERNEL_NAME     — ten dung cho UI + thu muc backup
#   3) 2 dong echo     — log cua post-boot script da cai vao may
#   4) banner          — dong Version/Variant (dang cu con ghi "BakaSU")
sed -i "s|^kernel.string=.*|kernel.string=${KNAME} Kernel (${LABEL}) ${VERSION}-${BRANCH} by WiL (@Steambot12) kang by tungtx0507|" \
    "$STAGE/anykernel.sh"
sed -i "s|^KERNEL_NAME=.*|KERNEL_NAME=\"${KNAME}\"|" \
    "$STAGE/anykernel.sh"
sed -i "s|echo \"Zyomi16 Kernel Post-Boot Init\"|echo \"${KNAME} Kernel Post-Boot Init\"|" \
    "$STAGE/anykernel.sh"
sed -i "s|echo \"Zyomi16 power tuning applied:|echo \"${KNAME} power tuning applied:|" \
    "$STAGE/anykernel.sh"

# banner: giu van de chu "|Z|Y|O|M|I|1|6|" tru khi ten tuy chon; luon sua dong
# Version/Variant cho dung ten + dung nhan (khong de cu la "BakaSU")
if [ -f "$STAGE/banner" ]; then
    # Banner goc co rong noi = 41 ky tu (tong dong = 45). Giu dung kieu khung,
    # cat bot khi nhan root / ten kernel dai qua.
    bline() { printf "| %-41s |\n" "$(printf '%.41s' "$1")"; }
    if [ "$KNAME" = "Zyomi16" ]; then
        awk -v k="$KNAME" -v v="$LABEL" '
            /Version    :/ { printf "| %-41s |\n", substr("Version    : " k " Kernel", 1, 41); next }
            /Variant    :/ { printf "| %-41s |\n", substr("Variant    : " v, 1, 41); next }
            { print }' "$STAGE/banner" > "$STAGE/banner.new"
    else
        w=43; max=$(( w - 4 ))
        title="$(printf '%s KERNEL' "$KNAME" | tr '[:lower:]' '[:upper:]')"
        # qua dai -> bo suffix " KERNEL" truoc, van qua dai thi cat ngan
        [ ${#title} -gt "$max" ] && title="$(printf '%s' "$KNAME" | tr '[:lower:]' '[:upper:]')"
        [ ${#title} -gt "$max" ] && title="${title:0:$max}"
        len=${#title}
        padl=$(( (w - len) / 2 )); [ "$padl" -lt 0 ] && padl=0
        padr=$(( w - len - padl )); [ "$padr" -lt 0 ] && padr=0
        bar=$(printf '%*s' "$w" '' | tr ' ' '-')
        {
            printf "+%s+\n" "$bar"
            printf "|%*s%s%*s|\n" "$padl" "" "$title" "$padr" ""
            printf "+%s+\n" "$bar"
            bline "Version    : ${KNAME} Kernel"
            bline "Kernel Base: android12-5.10 Linux Stable"
            bline "Variant    : ${LABEL}"
            printf "+%s+\n" "$bar"
        } > "$STAGE/banner.new"
    fi
    mv -f "$STAGE/banner.new" "$STAGE/banner"
fi

# --- goi zip -----------------------------------------------------------------
OUT_DIR="${OUT_DIR:-.}"
mkdir -p "$OUT_DIR"
ZIP_PATH="${OUT_DIR}/${NAME}.zip"
rm -f "$ZIP_PATH" "$ZIP_PATH.sha256" "${OUT_DIR}/${NAME}.txt"

( cd "$STAGE" && zip -r9q "$ZIP_PATH" . -x "*.git*" )

# --- 15) verify noi dung zip -------------------------------------------------
[ -f "$ZIP_PATH" ] || die 15 "khong tao duoc zip: ${ZIP_PATH}"
listing=$(unzip -l "$ZIP_PATH")
fail=""
echo "$listing" | grep -qE "[[:space:]]anykernel\.sh\$"            || fail="${fail} anykernel.sh"
echo "$listing" | grep -qE "[[:space:]]${img_name}\$"              || fail="${fail} ${img_name}"
echo "$listing" | grep -q "META-INF/com/google/android/update-binary" || fail="${fail} META-INF/update-binary"
if [ -n "$fail" ]; then
    echo "--- noi dung zip:"; echo "$listing" | head -30 >&2
    die 15 "zip thieu file bat buoc:${fail}"
fi

# --- checksum + file thong tin ----------------------------------------------
( cd "$OUT_DIR" && sha256sum "${NAME}.zip" > "${NAME}.zip.sha256" )
zip_size=$(du -h "$ZIP_PATH" | cut -f1)

{
    echo "$KNAME Kernel — build info"
    echo "==========================="
    echo "Kernel name    : ${KNAME}"
    echo "Kernel version : ${VERSION}"
    echo "Branch         : ${BRANCH}"
    echo "Commit         : ${COMMIT:-unknown}"
    echo "Root solution  : ${ROOT}"
    echo "Multi Manager  : ${MM}"
    echo "SUSFS          : ${SUSFS}"
    echo "Droidspaces    : ${DROID}"
    echo "AK3 variant    : ${AK3_VARIANT}"
    echo "Image          : ${img_name} ($(( img_size / 1048576 ))MB)"
    echo "Zip            : ${NAME}.zip (${zip_size})"
    echo "Zip sha256     : $(cut -d' ' -f1 < "${OUT_DIR}/${NAME}.zip.sha256")"
    echo "Build date     : $(date '+%Y-%m-%d %H:%M %Z')"
    if [ ${#WARNINGS[@]} -gt 0 ]; then
        echo ""
        echo "CẢNH BÁO:"
        i=1
        for w in "${WARNINGS[@]}"; do
            echo "  $i. $w"
            i=$(( i + 1 ))
        done
    fi
    echo ""
    echo "Cach flash: TWRP/OrangeFox → chọn ${NAME}.zip → Reboot"
    echo "Canh bao: lần đầu hãy backup boot (zip AK3 tự backup vào"
    echo "  /sdcard/Zyomi16Kernel_Backup(nguon du phong khi bootloop))"
} > "${OUT_DIR}/${NAME}.txt"

echo ""
echo "[✓] Da goi: ${ZIP_PATH} (${zip_size})"
echo "[✓] Checksum: ${OUT_DIR}/${NAME}.zip.sha256"
echo "[✓] Thong tin: ${OUT_DIR}/${NAME}.txt"
echo ""
cat "${OUT_DIR}/${NAME}.txt"
