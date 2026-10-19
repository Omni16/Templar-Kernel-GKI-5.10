# vendor/ — build bộ "vendor" (boot + vendor_boot + vendor_dlkm + dtbo) cho marble

Pipeline CI: `.github/workflows/Zyomi-vendor.yml` (job "Build Vendor"). Khác workflow GKI
(`Zyomi-kernel.yml` — chỉ thay boot):

- Thay đồng bộ **bộ phân vùng đích**: `boot` (Image), `vendor_boot` (ramdisk modules + dtb),
  `vendor_dlkm` (image modules), `dtbo` (bản `dtbo-0` theo ROM MIUI). Flash lẻ = bootloop
  (đã chứng minh bằng thực nghiệm với bản GKI 2 option — xem `docs/build-history.md`).
- Bật được 2 option cấu hình **BREAK kABI** mà bản GKI thuần không thể:
  `CONFIG_CFS_BANDWIDTH=y` (cho `droidspaces --cpus`) + `CONFIG_CGROUP_PIDS=y` (`--pids-limit`).
  An toàn vì TOÀN BỘ module đều được build từ CÙNG một lần build với Image (không trộn module cũ).
- CHỈ hỗ trợ ROM **HyperOS/MIUI stock** (AK3 tự abort trên AOSP/OSS/AOSPA — guard trong `ak3-patch.py`).

## Nguồn & pin cứng

| Thành phần | Pin | Ghi chú |
|---|---|---|
| Kernel tree | `Pzqqt/android_kernel_xiaomi_marble` @ `44b755a48379c5dcce588c3425d4e9fd5efd0052` | nhánh `bouquet_ci` — **superset** của dòng Melt (chứa `melt-rebase` + `arch/arm64/boot/dts/vendor` + `build-tools`); kernelversion 5.10.272 |
| Defconfig | `vendor/marble-melt_defconfig` (byte-identical m4lg@`3097a527`) | dòng Melt: touch MIUI `GOODIX_BRL_9916` + `XIAOMI_TOUCHFEATURE` + module MIUI (`XLOGCHAR`, `BINDER_PRIO`, `EXTEND_RECLAIM`, `MI_CNSS_STATISTIC`, `KSHRINK_LRUVECD`…). Build ép thêm `CONFIG_BUILD_ARM64_DT_OVERLAY=y` (melt thiếu; Makefile dts vendor bọc trong ifeq này) |
| AnyKernel3 | `Pzqqt/AnyKernel3` @ `699488a82672b6957bc48dc52ed0c43b3546c7c5` (nhánh `Marble-Melt`) | patch bằng `vendor/ak3-patch.py` (assert từng vị trí — lệch là fail) |
| Root | BakaSU `v4.2.0-rc3` @ `239e1e8871b8fcd51a6e5b3002e0ba522fdd99fb` | bake vào Image (`drivers/kernelsu`) |
| SUSFS | `simonpunk/susfs4ksu` nhánh `gki-android12-5.10` @ `31eb14add587` (**pin cứng** — workflow `git checkout` đúng commit, không dùng tip) | chỉ patch `50_add_…` + copy `kernel_patches/{fs,include/linux}`. Lý do pin: từ upstream `5a3af83e` ("Sync with official KernelSU main repo") patch 50_add gọi `ksu_preinit_*` của KernelSU main — BakaSU rc3 không định nghĩa → link vmlinux fail undefined symbol (run 39210253573); guard trong workflow fail sớm nếu vi phạm |
| Toolchain | Slim LLVM `llvm-23.1.3-x86_64` + `7za` 26.03 | cache theo key; KHÔNG dùng llvm của apt |

Lưu ý quan trọng: mọi nhánh Melt thuần (`melt`, `melt-rebase*`, tag `Melt-marble-v5.2`) **không có**
`arch/arm64/boot/dts/vendor` + `build-tools` → không build được dtb/dtbo. Vì vậy tree = `bouquet_ci`
(đã kiểm: `behind: 0` so với `melt-rebase-4LazyGoogle`), còn config = defconfig Melt.

## Pipeline (các bước trong workflow)

1. Validate inputs (sha 40 hex; tên kernel không chứa Melt/Bouquet/Pzqqt).
2. Checkout `vendor/` (sparse) + check đủ file CI (gồm `marble-melt_defconfig`).
3. Free disk + swap 10GB + deps + LLVM + 7za.
4. Clone kernel @ `tree_ref` (fetch theo sha; fallback clone nhánh `bouquet_ci`), check cây
   **có dts vendor** + `techpack` + `marble_defconfig`.
5. build-tools: ưu tiên bản trong tree (`kernel/build-tools/`), fallback raw `TOOLING_REF`;
   `avbtool/fdtget/fdtput/merge_dtbs.py/mkdtboimg.py` phải có trên PATH.
6. Clone BakaSU (verify sha) + SUSFS + AK3 (verify sha) → patch AK3 (rebrand Zyomi16; bỏ prompt
   KSU-patch/360Hz/real-battery/zram-MI/GPU/ntsync; chặn ROM non-MIUI; tên zip).
7. Build (`vendor/build-zyomi-vendor.sh`): BakaSU → SUSFS → nạp defconfig Melt →
   LOCALVERSION/LTO-full/DT_OVERLAY → fragment 22 config + KSU/MM/SUSFS configs →
   verify `out/.config` (**fail cứng** nếu thiếu bất kỳ mục nào) → `make` LTO full →
   Image + symvers + modules (strip) + devicetree (merge_dtbs + mkdtboimg + avbtool).
8. Package AK3: `modify_dtb_and_dtboimg.sh` (dtb + dtbo-0/1) → nhét modules + Image →
   `make_package.py` (depmod_regen + simulate_load + 7z + nhúng sha1 Image).
9. Verify zip (đủ mục; placeholder SHA1 đã thay; kernel.string đúng; uname đúng trong Image)
   → artifact: zip + `.sha256` + `build-info.txt` + `modules-report.txt` + `out.config`.

## Tên zip / uname

- zip: `Zyomi16-<KVER>-Vendor-BakaSU+SUSFS+MultiMgr+Droidspace-<YYYYMMDD_HHMM>.zip`
- `uname -r` = `<KVER>-Zyomi16-<tree_sha12>` (`CONFIG_LOCALVERSION` + env `LOCALVERSION`)

## Claims (đều verify trong out/.config trước khi đóng gói)

`LTO_CLANG_FULL=y` (+ `LTO_CLANG=y` là bool ẩn được select, THIN/NONE off) · `CFI_CLANG=y` ·
`MODVERSIONS=y` · `KSU=y` + `KSU_MULTI_MANAGER_SUPPORT=y` + `KSU_SUSFS=y` (+10 sub-flag) ·
fragment **22/22** (20 kABI-safe + `CFS_BANDWIDTH` + `CGROUP_PIDS`) · `BUILD_ARM64_DT_OVERLAY=y` ·
`UNAME_OVERRIDE` OFF (xung đột `KSU_SUSFS_SPOOF_UNAME`) · `LOCALVERSION="-Zyomi16"`.

## Module lists (vendor/modules/)

- Nguồn: **copy basename từ `build_bouquet.sh`@44b755a** (`both_need_modules` 199 +
  `vendor_boot_need_modules` 100 + `vendor_dlkm_need_modules` 56 → ship 299/255), GIỮ rename
  duy nhất `qca6490.ko → qca_cld3_qca6490.ko`.
- Đã đối chiếu 1:1 với zip thật `Bouquet-Kernel-v5.2.zip`: vb 298/299 (lệch duy nhất
  `kshrink_lruvecd.ko` — bản ta có vì defconfig Melt bật `KSHRINK_LRUVECD=m`), vd 255/255.
- `known-missing.txt`: `cpq.ko` (config `CPQ_IOSCHED` chỉ có ở dòng Bouquet) — WARN, chấp nhận.
- `load/`: `modules.load` (+ `.recovery`, `.blocklist`, `.options`) — lấy từ zip thật;
  `gen-module-dirs.py` **lọc theo bộ ship** (giữ nguyên thứ tự gốc, không append).

## Giới hạn v1 (đọc trước khi flash)

1. **Lists chưa đối chiếu dump stock máy thật.** Bộ v1 = lists dòng Bouquet; các module MIUI mà
   defconfig Melt build nhưng list không có (vd `binder_prio`, `extend_reclaim`, `xlogchar`,
   `mi_cnss_statistic`, `millet_*`…) sẽ **không được ship**. AK3 wipe module stock ở cả
   vendor_boot lẫn vendor_dlkm rồi thay bằng bộ của ta ⇒ tính năng MIUI dùng module đó sẽ thiếu
   (không phải lỗi boot — load lists của ta cũng đã lọc theo bộ ship, boot vẫn nhất quán).
   **v2**: tạo lại lists + load lists từ dump `vendor_boot.img` + `vendor_dlkm` của chính máy,
   so khớp 1:1 rồi mới khuyến nghị flash thật.
2. **zram/zsmalloc = bản OSS dựng từ cây.** AK3 gốc cho chọn bản MI-zram/MI-zsmalloc prebuilt
   của Pzqqt (pipeline riêng, không tái tạo được từ nguồn công khai) — v1 dùng bản build từ tree
   (đúng "OSS variant" nằm trong danh sách lựa chọn của AK3 gốc). Trên MIUI có thể thiếu phần
   thống kê zram của MIUI.
3. **ntsync đã gỡ** (không ship v1). Các prompt GPU giả Adreno730v3 / 360Hz-OC / real-battery /
   KSU-patch đã gỡ (giữ hành vi stock).
4. `_alt/` đã xoá khỏi zip — mọi tham chiếu `_alt` còn lại trong anykernel.sh
   (`OSS-ir-spi`, `OSS-sched-walt`) đã chứng minh **không thể chạm trên MIUI**
   (bị `if ${is_miui_rom}` / `if ! ${is_miui_rom}` chặn trước).
5. **Flash chạm cả `dtbo` + `vbmeta*`**: luồng Melt AK3 flash `boot` + `vendor_boot` +
   `vendor_dlkm` + `dtbo` (bản MIUI) và chạy `vbmeta-disable-verification` (chuẩn của AK3 gốc).
   Backup zip do AK3 tạo ra chứa đủ kernel + vendor_boot + dtbo + vendor_dlkm gốc để restore.

## Cách chạy

```bash
R=Omni16/Templar-Kernel-GKI-5.10
gh workflow run Zyomi-vendor.yml --repo $R --ref Templar-LinuxStable
sleep 10
ID=$(gh run list --repo $R --workflow Zyomi-vendor.yml --limit 1 --json databaseId -q '.[0].databaseId')
gh run watch $ID --repo $R
```

Build ~60–120 phút (LTO full + dts vendor + module strip). Artifact giữ **15 ngày**.

## V2 plan (khi có stock)

1. Dump từ máy/user: `vendor_boot.img` (từ ROM zip) + `vendor_dlkm.img` (dd phân vùng).
2. Liệt kê module 2 phía → so với bộ build; bổ sung module MIUI còn thiếu vào
   `both.txt`/`vendor_boot.txt`/`vendor_dlkm.txt` + thêm entry vào load lists (đúng vị trí/thứ tự
   stock); cân nhắc `_alt` entries.
3. Đối chiếu 1:1 tên + load lists 2 phía trước khi khuyến nghị flash thật.
