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
| SUSFS | `simonpunk/susfs4ksu` nhánh `gki-android12-5.10` @ `31eb14add587` (**pin cứng** — workflow `git checkout` đúng commit, không dùng tip) | chỉ patch `50_add_…` + copy `kernel_patches/{fs,include/linux}`. Lý do pin: từ upstream `5a3af83e` ("Sync with official KernelSU main repo") patch 50_add gọi `ksu_preinit_*` của KernelSU main — BakaSU rc3 không định nghĩa → link vmlinux fail undefined symbol (run 39210253573); guard trong workflow fail sớm nếu vi phạm. Khi GitLab chặn smart-git (load — run 39240844304), workflow fallback: resolve prefix→full SHA qua API + tải `/-/archive/<full>` và verify thư mục gốc `susfs4ksu-<full>` — vẫn đúng pin, không nới kiểm tra |
| Vá driver goodix | `vendor/patches/goodix-9916r-fix-gesture-container-of.patch` | `goodix_ts_core.c` variant MIUI (`XIAOMI_TOUCHFEATURE`): `container_of(work, …)` trỏ vào member `delayed_work` → check `container_of()` của kernel bung thành ld.lld `dontcall-error` khi codegen LTO FULL module `goodix_core` (run 39216833751). Sửa đúng theo pattern bản LOS trong cùng file (`to_delayed_work`) — runtime không đổi (work_struct là member đầu của delayed_work) |
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
7. Build (`vendor/build-zyomi-vendor.sh`): BakaSU → SUSFS → vá `goodix_ts_core.c` (container_of
   cho LTO full) → nạp defconfig Melt → LOCALVERSION/LTO-full/DT_OVERLAY → fragment 22 config +
   KSU/MM/SUSFS configs → verify `out/.config` (**fail cứng** nếu thiếu bất kỳ mục nào) →
   `make` LTO full → Image + symvers + modules (strip) + devicetree (merge_dtbs + mkdtboimg + avbtool).
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

## Module lists (vendor/modules/) — v2 (19-10-2026)

- **Nguồn v2**: dump stock máy user — `vendor_boot.img` (ramdisk, VNDRBOOT v4) +
  `vendor_dlkm_a.img` (EROFS slot a) — đối chiếu với **371 .ko build thật** của run
  `39222558504` (trích dòng `LD [M]` từ log). Stock: vb 356 / vd 312 module.
- **Ship v2**: vendor_boot **315**, vendor_dlkm **265** (stock ∩ buildable + 4 module riêng
  `hdcp`, `vh_fs`, `kshrink_slabd`, `kshrink_lruvecd`). Phân vùng theo stock:
  `cfg80211`/`mac80211` → vendor_boot; riêng `xiaomi_touch.ko` ship **cả 2 phía** vì
  `goodix_core.ko` (vendor_boot + `modules.load.recovery`) import 6 symbol của nó — pass
  simulate recovery chỉ đọc thư mục vendor_boot (v1 cũng ship both).
- **known-missing.txt**: 56 tên stock có mà cây Melt không build (touch IC khác, coresight/stm,
  `millet_*`, MIUI framework…) — WARN trong log, không FAIL; lý do nhóm ghi trong file.
- Rename duy nhất: `qca6490.ko → qca_cld3_qca6490.ko` (profile `CONFIG_QCA_CLD_WLAN_PROFILE="qca6490"`;
  stock còn ship `qca_cld3_qca6750.ko` — không build được từ cây). Không ship dù build được:
  `ntsync.ko` (cố ý bỏ), `cs35l41_dlkm.ko` (stock không có).
- **load/ v2**: thứ tự **theo stock** từng phân vùng, lọc theo bộ ship; entry riêng của ta
  (`hdcp`, `vh_fs`, `kshrink_*`) chèn lại đúng vị trí tương đối v1; `kshrink_lruvecd.ko`
  nay **có** entry (v1 thiếu). `modules.load.recovery` **thêm `xiaomi_touch.ko` ngay trước
  `goodix_core.ko`** (như v1): simulate của Pzqqt chỉ load module **có trong list** — dep
  ngoài list bị bỏ qua, nên thiếu entry là `Unknown symbol` (run 39242464729).
  `blocklist`/`options` giữ nguyên (đã khớp stock).

## Giới hạn v1 (đọc trước khi flash)

1. **Lists v2 đã đối chiếu dump stock máy thật** (19-10): vb 356 / vd 312 → ship 315/265;
   phần không ship được = 56 tên trong `known-missing.txt` (cây Melt không build). Đây là gap
   chấp nhận, có WARN chi tiết trong build log — không phải lỗi boot (load lists đã lọc khớp
   bộ ship; `simulate_load_kernel_modules` của Pzqqt kiểm tra trước khi đóng gói).
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

## Đối chiếu v2 — provenance (đã thực hiện 19-10-2026)

1. Dump từ máy: `vendor_boot.img` (ramdisk `lz4_legacy`) + `vendor_dlkm_a.img` (EROFS slot a).
2. Trích: `tools/extract.erofs` + `magiskboot unpack` + `busybox cpio` (AK3 tools aarch64);
   inventory bộ ta = dòng `LD [M]` trong log run `39222558504` (371 .ko).
3. Sinh lại 3 list + `known-missing.txt` + load baseline; dry-run `gen-module-dirs.py` local:
   0 tên load bị bỏ, 0 module ship thiếu entry load (v1 lệch `kshrink_lruvecd`).
