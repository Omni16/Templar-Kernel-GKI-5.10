# AGENTS.md — Quy trình CI repo Zyomi16 (Templar-Kernel-GKI-5.10)

Repo `Omni16/Templar-Kernel-GKI-5.10` là **fork của `Steambot12/Templar-Kernel-GKI-5.10`**.
Nhánh làm việc: `Templar-LinuxStable` (mọi dispatch dùng nhánh này). Người giữ repo: @Omni16.

> **Bối cảnh (17-10-2026): repo tái tạo sạch.** Repo cũ đã bị xóa để loại hoàn toàn các
> biến thể nghi ngờ gây bootloop. Bản này = Steambot12 tip `dd912355af` + lớp CI/đóng gói.
> **KHÔNG mang theo** (khác repo cũ):
> - block backport GKI 6.1 — thực chất 9 config thật: `SYN_COOKIES`, `SOFTLOCKUP_DETECTOR`,
>   `BLK_CGROUP_IOPRIO`, `BLK_DEV_THROTTLING`, `IPV6_MROUTE`, `MACSEC`,
>   `NETFILTER_XT_MATCH_CONNBYTES`, `CPU_IDLE_GOV_TEO`, `DAMON_VADDR`;
> - CMDLINE diag (`loglevel=15` + `initcall_debug`);
> - tinh chỉnh cũ: ZRAM/ZPOOL/ZSMALLOC off, MODVERSIONS=n, SUSPEND_SKIP_SYNC,
>   DAMON_RECLAIM, BPF_LIRC_MODE2, SLUB_DEBUG off.
>
> Muốn đưa lại bất kỳ mục nào: **1 commit — 1 nguyên nhân — build đối chứng**.

> **Quy tắc trên tất cả quy tắc:** không bao giờ "sửa cho xanh".
> Build xanh bằng cách bịt mắt kiểm tra là build tệ hơn build đỏ.

## 1. Thành phần

| Thành phần | Vị trí |
|---|---|
| Workflow chính | `.github/workflows/Zyomi-kernel.yml` |
| AnyKernel3 (vendored) | `anykernel3/` |
| Biến thể AK3 | `ak3/anykernel-gki.sh` (GKI), `ak3/anykernel-nongki.sh` |
| Script đóng gói | `scripts/package-ak3.sh` ⚠️ nằm chung thư mục `scripts/` của kernel — xem §8 |
| Droidspaces fragment | `config/droidspaces.fragment` (20 config, kABI-safe) |
| Lịch sử build | `docs/build-history.md` |
| Bảng thiết bị | `DEVICES.md` |

## 2. Inputs workflow (18 input)

`kernel_name` (→ `CONFIG_LOCALVERSION` + tên zip), `bakasu` (+`bakasu_branch`),
`sukisu_ultra` (+`sukisu_branch`), `ksu_next` (+`ksu_next_branch`, `ksu_next_repo`),
`agnesu` (+`agnesu_branch`), `kittisu` (+`kittisu_branch`), `mambosu` (+`mambosu_branch`),
`multi_manager`, `enable_susfs` (+`susfs_branch`), `droidspaces`.

Luật tổ hợp (job `validate-inputs`, fail sớm + in lý do):
- Tick nhiều root → build root ưu tiên: BakaSU > AgnesSU > KittiSU > SukiSU-Ultra > KSU-Next > MamboSU;
  Multi Manager **bật tự động** (các driver KernelSU loại trừ nhau) — CHỈ khi root thắng là
  BakaSU/AgnesSU/KittiSU; nếu root thắng là SukiSU-Ultra/KSU-Next/MamboSU (không có MM)
  thì tự hạ `MM=false` + cảnh báo (trước đây bật MM sai → verify Build fail oan).
- `mambosu` = `RapliVx/KernelSU` nhánh `xxksu` (MamboHook: syscall table + LSM; app
  `com.rapli.mambosu`) — **không có KSU_SUSFS / MULTI_MANAGER_SUPPORT**: tick kèm SUSFS →
  **FAIL sớm** ở validate. Build tự bật `CONFIG_KSU_TAMPER_SYSCALL_TABLE=y` + tắt
  `CONFIG_KPROBES` (đúng README nhánh xxksu). Bước Build **FAIL cứng** nếu `out/.config`
  thiếu `CONFIG_KSU_TAMPER_SYSCALL_TABLE=y`.
- `enable_susfs=true` mà không tick root nào → **FAIL**.
  SukiSU-Ultra chỉ đi với SUSFS khi branch `builtin` (đã xác minh bằng grep thật).
- Droidspaces + SUSFS: workflow cảnh báo phải tắt "HIDE SUS MOUNTS FOR ALL PROCESSES"
  trong app SUSFS4KSU, nếu không container sẽ boot fail.
- `kernel_name`: `[A-Za-z0-9._-]`, ≤ 32 ký tự.

Bất biến (đừng phá):
- **LTO full**: workflow sửa defconfig để `CONFIG_LTO_CLANG_FULL=y` (THIN/NONE tắt) và
  **FAIL cứng** nếu `out/.config` không có `FULL=y`. Lưu ý: kconfig chỉ chọn được LTO khi
  chạy bằng clang/LLD (`HAS_LTO_CLANG`); eval cục bộ bằng gcc luôn ra `LTO_NONE=y` —
  đó là artefact cục bộ, không phải lỗi.
- **LOCALVERSION** = `-$kernel_name`; `LOCALVERSION_AUTO` luôn tắt (uname tái lập được).
- **Droidspaces**: kABI fix SYSVIPC (`ANDROID_KABI_USE(6, struct sysv_sem` trong
  `include/linux/sched.h`) và POSIX_MQUEUE (`ANDROID_KABI_USE(1, unsigned long mq_bytes`
  trong `include/linux/sched/user.h`) **đã có sẵn trong cây Steambot12** → bước patch
  skip là ĐÚNG thiết kế (nếu tương lai thiếu, workflow tự áp 1 trong 3 biến thể
  001/002 và fail rõ nếu không được). Sau đó verify đủ **20 config** fragment trong
  `out/.config` trước khi đóng gói.
- **SUSFS**: clone HEAD nhánh `gki-android12-5.10` của `simonpunk/susfs4ksu` (không pin
  commit); verify `CONFIG_KSU_SUSFS=y` trong `out/.config` (đã đo: patch `50_add` apply
  sạch trên cây này, 17-10, commit `ca7093a`).
- Nếu tên zip ghi `+SUSFS` / `+MultiMgr` / `+Droidspace` thì `out/.config` phải chứng
  minh đủ tính năng, thiếu là fail — không được đổi tên cho khớp.

## 3. Dispatch & theo dõi

```bash
R=Omni16/Templar-Kernel-GKI-5.10
gh workflow run Zyomi-kernel.yml --repo $R --ref Templar-LinuxStable \
  -f kernel_name=Zyomi16 -f bakasu=true -f sukisu_ultra=false \
  -f multi_manager=true -f enable_susfs=true -f droidspaces=true
sleep 10
ID=$(gh run list --repo $R --limit 1 --json databaseId -q '.[0].databaseId')
gh run watch $ID --repo $R
```

Build ~27–35 phút (4 vCPU). Artifact giữ **15 ngày**: zip + `.sha256` + `.txt` (manifest) + Image thô.

Khi fail — tìm **lỗi đầu tiên** (không phải lỗi cuối):

```bash
JOB=$(gh api repos/$R/actions/runs/$ID/jobs --jq '.jobs[0].id')
gh run view $ID --repo $R --job "$JOB" --log | \
  grep -aE '##\[error|::error|error:|fatal:|No such file|patch does not apply' | head -20
```

## 4. Phân loại lỗi → cách sửa nhỏ nhất

| Nhóm | Dấu hiệu | Sửa nhỏ nhất |
|---|---|---|
| Workflow YAML | `Invalid workflow file`, `Unrecognized named-value` | Sửa expression/input cho khớp; **không** đổi logic build |
| Checkout AK3 | thiếu `anykernel3/`, sparse rỗng | Kiểm tra pattern sparse-checkout từng path (`/anykernel3/`, `/ak3/`, `/config/`, `/scripts/package-ak3.sh`) |
| Toolchain | `clang: not found`, tar hỏng | Đổi mirror Clang; giữ `LLVM=1 LLVM_IAS=1` |
| Clone kernel | `Remote branch ... does not exist` | Kiểm tra branch tồn tại; **không** lách sang nhánh khác |
| Root (BakaSU/...) | `drivers/Makefile chua duoc sua` | Kiểm tra symlink `drivers/kernelsu` + `obj-$(CONFIG_KSU) += kernelsu/` + `source "drivers/kernelsu/Kconfig"` |
| SUSFS | `SUSFS khong xuat hien trong kernel source` | Copy đủ `kernel_patches/{fs,include/linux}` rồi patch (thứ tự: root trước, SUSFS sau) |
| Droidspaces | `Khong ap duoc SYSVIPC kABI patch` | Cây base thiếu fix kABI — KHÔNG được bật `CONFIG_SYSVIPC` khi fix chưa chắc (bootloop) |
| LTO full | `CONFIG_LTO_CLANG_FULL khong =y` | Kiểm tra sed defconfig + toolchain clang có LLD |
| Compile | `error:` trong `make`, OOM | Sửa code/config gốc; tăng swap/`-j`; không nới `-Wno-error` hàng loạt |
| Đóng gói | `[LOI 10..17]` từ `package-ak3.sh` | Xem mục mã lỗi trong script |
| Upload | `if-no-files-found: error` | Kiểm tra file được tạo thật; **không** hạ xuống `warn` |

## 5. Giới hạn & kỷ luật

- **Tối đa 3 lần cho mỗi loại lỗi.** Quá 3 lần mà chưa xong → dừng, ghi rõ nguyên nhân
  + 2 phương án đề xuất, rồi hỏi.
- Mỗi lần sửa = **một commit nhỏ, một nguyên nhân**. Message nói rõ *tại sao*.
- Verify trước push: `yaml.safe_load`, `actionlint`, `bash -n` các khối `run:`;
  khi đụng config thì chạy eval Kconfig cục bộ.
- **PHẢI HỎI trước** khi: xóa nhánh/run/artifact, đổi `permissions:`, force-push.
- Push sửa lỗi thường lệ lên `Templar-LinuxStable` thì được, nhưng **báo lại ngay** sau khi đẩy.

## 6. Cấm "sửa cho xanh"

- Không bỏ / hạ ngưỡng: verify LTO full, verify 20 config Droidspaces, verify
  `CONFIG_KSU_SUSFS=y` + `CONFIG_KSU_MULTI_MANAGER_SUPPORT=y`, `git apply --check` kABI,
  verify zip (`if-no-files-found: error` giữ nguyên).
- Không xóa input/fragment/chức năng chỉ vì nó đang gây lỗi — sửa nguyên nhân gốc.
- Nếu bản thân **phép kiểm tra** sai (không phải build sai): sửa cấu hình của phép kiểm
  tra đó cho đúng, ghi rõ trong commit tại sao.

## 7. Khi build thành công

1. `gh run download $ID --repo $R --dir /tmp/artifact`; `sha256sum -c *.sha256`.
2. `unzip -l *.zip | grep -E 'anykernel.sh|variant.prop|META-INF/com/google/android/update-binary'`;
   `unzip -p *.zip variant.prop` — phải khớp phiên bản vừa build.
3. Ghi **1 dòng** vào `docs/build-history.md` (mẫu trong file), commit
   `docs: ghi nhận build <ID>`.
4. Báo user: tên zip, sha256, link run, thời gian build.

## 8. Ghi chú kỹ thuật hay mắc

- `scripts/` là thư mục của **kernel**: không `git add` cả thư mục, chỉ đụng
  `package-ak3.sh`. Sparse-checkout của workflow dùng pattern **từng path**.
- AK3 vendor = base upstream **2026-09-04**; core mới **chỉ nhận biến CHU HOA**:
  `BLOCK=boot` (tên phân vùng trần vẫn được), `IS_SLOT_DEVICE=auto`,
  `RAMDISK_COMPRESSION=auto`, `PATCH_VBMETA_FLAG=auto` — compat chữ thường của core
  2024 đã bị bỏ. `flash_dtbo` không còn → nongki dùng `flash_generic dtbo` (có fallback
  nếu vẫn chạy core cũ). `devicecheck=0` và không điền `device.name1` → zip flash được
  trên mọi máy GKI 5.10 tương thích (xem `DEVICES.md`).
- Zip **không** đóng gói `dtbo.img` / `vendor_boot` / `vendor_dlkm` (giữ phân vùng zin).
- ReSukiSU ≡ BakaSU (`ReSukiSU/ReSukiSU` redirect về `Baka-SU/BakaSU` — cùng repo).
- Base Steambot12 có `CONFIG_MODVERSIONS=y` (khác bản #10 cũ = `n`); summary in giá trị
  này + vermagic để đối chiếu khi cần.
- `actionlint` trên workflow này có 3 info shellcheck "cũ" (SC2015/SC2012/SC2086) —
  tồn tại từ trước, không phải lỗi mới cần chữa.
