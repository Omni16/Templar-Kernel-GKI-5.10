> ⚠️ **17-10-2026 — repo đã được tái tạo sạch** (fork Steambot12, tip `dd912355af`, sau
> chuỗi sự cố bootloop). Các run bên dưới thuộc **repo tiền nhiệm** (bản cũ của
> Omni16/Templar-Kernel-GKI-5.10 — đã xóa); link không còn mở được, giữ lại làm nhật ký
> kiến thức. Build đầu tiên của repo mới sẽ được ghi thêm lên đầu bảng.

# Build history

Nhật ký build của `Zyomi-kernel.yml`. **Mỗi lần build thành công ghi
đúng MỘT DÒNG** ở đầu bảng (mới nhất lên trên). Không xóa dòng cũ.

Cột:

| Cột | Ý nghĩa |
|---|---|
| Ngày | Giờ địa phương (Asia/Ho_Chi_Minh) |
| Run | `gh run view <ID>` — dùng để tải lại log/artifact |
| Nhánh | `kernel_branch` đã chọn |
| Phiên bản | Từ `make kernelversion` (KHÔNG được hardcode) |
| Root | ReSukiSU / SukiSU-Ultra / Vanilla, kèm `+MultiMgr` nếu bật |
| SUSFS | `on` (ghi cả commit của `susfs4ksu`) hoặc `off` |
| Droidspaces | `on` (kABI-safe) hoặc `off` |
| Zip | Tên artifact chính xác |
| Trạng thái | ✅ build OK / ❌ build fail / 📱 đã flash thử lên máy |
| Ghi chú | Rủi ro, điều chưa xác minh, lý do fail |

---

## Bảng
| Ngày | Run | Nhánh | Phiên bản | Root | SUSFS | Droidspaces | Zip | Trạng thái | Ghi chú |
|---|---|---|---|---|---|---|---|---|---|
| 2026-10-18 18:12 | [39120819942](https://github.com/Omni16/Templar-Kernel-GKI-5.10/actions/runs/39120819942) | Templar-LinuxStable | 5.10.271 | BakaSU + MultiMgr | on (`gki-android12-5.10@c06d5f8e`) | on (thử nghiệm: +CFS_BANDWIDTH +CGROUP_PIDS) | Zyomi16-5.10.271-Templar-LinuxStable-BakaSU+SUSFS+MultiMgr+Droidspace-20261018_1812.zip | 📱 bootloop | **Thực nghiệm kABI có kiểm soát — kết quả: bootloop trên máy.** Fragment 20→22 config để thử `--cpus`/`--pids-limit` Droidspaces; `.config` trong Image xác nhận 2 option `=y`. Máy bootloop (logo lên/tắt lặp) → đúng tài liệu: máy stock từ chối 2 option kABI-break. Đã revert `02b4a93`. Workflow: `71e2d58`. |
| 2026-10-18 16:02 | [39111720191](https://github.com/Omni16/Templar-Kernel-GKI-5.10/actions/runs/39111720191) | Templar-LinuxStable | 5.10.271 | BakaSU + MultiMgr | on (`gki-android12-5.10@c06d5f8e`) | on (kABI-safe) | Zyomi16-5.10.271-Templar-LinuxStable-BakaSU+SUSFS+MultiMgr+Droidspace-20261018_1602.zip | 📱 flash OK | **Bản chuẩn đang dùng (đã flash, boot xanh trên máy).** Fragment đúng 20 config kABI-safe. Workflow: `86a5233d3`. |
| 2026-10-10 17:37 | [38045513804](https://github.com/Omni16/Templar-Kernel-GKI-5.10/actions/runs/38045513804) | Templar-LinuxStable | 5.10.271 | BakaSU + MultiMgr | on (`9892175`) | off | — | ❌ | **Build bi HUY theo yeu cau, nhung da chung minh duoc phan quan trong cua viec gop job.** Tieu de run gio chi la `Build Templar Kernel` (da xoa `run-name`). Buoc `Validate inputs` *(step hop nhat tu job rieng)* = success, va **6 cho output** sang `Clone Kernel Source` (V_NAME/V_ROOT/V_MM/V_SUSFS/V_DROID/V_LABEL) da nhan dung gia tri — chung minh cu phap `steps.resolve.outputs.*` hoat dong. `Integrate Root Solution` + `Integrate SUSFS` cung xanh. Bi huy luc dang o `Build Kernel Image` -> **khong co zip, khong co artifact.** **4 cho output CHUA duoc chay that**: 3 cho o `Package AK3` (V_NAME/V_LABEL/V_WARNINGS) va 1 cho o `Generate Build Summary` (V_WARNINGS). |
| 2026-10-10 16:24 | [38039569879](https://github.com/Omni16/Templar-Kernel-GKI-5.10/actions/runs/38039569879) | ci-fix/ui-inputs | 5.10.271 | BakaSU + MultiMgr | on (`9892175`) | on | `TemplarVerify-5.10.271-ci-fix-ui-inputs-BakaSU+SUSFS+MultiMgr+Droidspace-20261010_1624.zip` | ✅ | **Build xanh dau tien chung minh DAMON da vao kernel.** Nghiemitu `.config` that (6871 dong, trich tu `Image`): `CONFIG_DAMON=y`, `CONFIG_DAMON_PADDR=y`, `CONFIG_DAMON_RECLAIM=y` — build truoc co **0 dong** chua `DAMON`. `CONFIG_SUSPEND_SKIP_SYNC=y` + `CONFIG_BPF_LIRC_MODE2=y` (truoc do ca 2 la `is not set`). `CONFIG_LOCALVERSION="-TemplarVerify"`; `CONFIG_MODVERSIONS=y`; `CONFIG_CFS_BANDWIDTH`/`CONFIG_CGROUP_PIDS` van `not set` (kABI-safe); **19/19** config `config/droidspaces.fragment` = `y`. Bang chung manh hon: `Image` (50MB) chua chuoi `damon_reclaim.enabled`, `damon_reclaim.wmarks_mid`, `damon_reclaim.sample_interval`, `damon_reclaim.min_age` va `kdamond.%d` -> DAMON **da duoc bien dich va link vao vmlinux**, khong chi duoc ghi vao `.config`. sha256 `0183fb0bd87187a14096aeee1cce73fbfa7a2dae2a2c6f71057963426a271e69`. **Chua flash len may.** |
| 2026-10-10 15:50 | [38037564141](https://github.com/Omni16/Templar-Kernel-GKI-5.10/actions/runs/38037564141) | ci-fix/ui-inputs | 5.10.271 | BakaSU + MultiMgr | on (`9892175`) | on | — | ❌ | **Lan 2 cua cung mot bug ten file.** Buoc goi zip da QUA (ZIP_NAME dung dang `ci-fix-ui-inputs`), nhung tiep tuc fail o `Upload Raw Kernel Image`: `The artifact name is not valid: Image-ci-fix/ui-inputs-BakaSU+... Contains the following character: Forward slash /`. `actions/upload-artifact` cung khong chap nhan '/' (han che NTFS). Da sua: dua `BRANCH_SAFE` vao `$GITHUB_ENV` de buoc sau dung lai duoc. Quet toan bo 17 buoc + 9 cho dung `inputs.kernel_branch`: chi 2 cho tao ten file/artifact can chuan hoa, cac cho con lai (git clone, run-name, ten job, summary, `variant.prop`) deu PHAI giu ten nhanh goc. |
| 2026-10-10 14:42 | [38035348491](https://github.com/Omni16/Templar-Kernel-GKI-5.10/actions/runs/38035348491) | ci-fix/ui-inputs | 5.10.271 | BakaSU + MultiMgr | on (`9892175`) | on | — | ❌ | **Kernel build THANH CONG — FAIL o buoc dong goi.** Log la bang chung damon da vao kernel: `CC mm/damon/core.o`, `CC mm/damon/prmtv-common.o`, `CC mm/damon/paddr.o`, `CC mm/damon/reclaim.o`, `AR mm/damon/built-in.a`, sau do `LD vmlinux` + `SORTTAB vmlinux`. Nguyen nhan fail: `ZIP_NAME` dua nguyen ten nhanh vao ten file, nhanh `ci-fix/ui-inputs` co ky tu `/` nen ten file tro thanh duong dan thu muc khong ton tai -> `zip` loi I/O, exit 15. Day la bug co san, truoc do cham khong vao vi moi co 1 nhanh (khong co '/'). Da sua: `BRANCH_SAFE` (tr '/' '-') trong workflow + guard som trong `package-ak3.sh`. |
| 2026-10-10 11:50 | [38023822163](https://github.com/Omni16/Templar-Kernel-GKI-5.10/actions/runs/38023822163) | Templar-LinuxStable | 5.10.271 | BakaSU + MultiMgr | on (`9892175`) | on | `TemplarTestD-5.10.271-Templar-LinuxStable-BakaSU+SUSFS+MultiMgr+Droidspace-20261010_1150.zip` | ✅ | Build gop dau tien sau khi sua ten symbol REJECT. Da verify tu `.config` that (6862 dong, trich khoi `Image`): **19/19** config `config/droidspaces.fragment` = `y`; `CONFIG_LOCALVERSION="-TemplarTestD"`; `CONFIG_MODVERSIONS=y`. **Phat hien quan trong:** `CONFIG_DAMON` la config CHET — `.config` co 0 dong chua `DAMON`, `mm/damon/` chua tung duoc bien dich (nguyen nhan: `mm/Kconfig` thieu dong `source "mm/damon/Kconfig"`). **Chua flash len may.** |
| 2026-10-10 10:50 | [38020183801](https://github.com/Omni16/Templar-Kernel-GKI-5.10/actions/runs/38020183801) | Templar-LinuxStable | 5.10.271 | BakaSU | on (`9892175`) | off | `TemplarTestA-5.10.271-Templar-LinuxStable-BakaSU+SUSFS+MultiMgr-20261010_1050.zip` | ✅ | Lan A/5 cua ma tran xac nghiem form CI moi: BakaSU + SUSFS, khong Droidspaces. |
| 2026-10-10 10:48 | [38020189758](https://github.com/Omni16/Templar-Kernel-GKI-5.10/actions/runs/38020189758) | Templar-LinuxStable | 5.10.271 | BakaSU + MultiMgr | on (`9892175`) | off | `TemplarTestC-5.10.271-Templar-LinuxStable-BakaSU+SUSFS+MultiMgr-20261010_1048.zip` | ✅ | Lan C/5: cong them Multi Manager. |
| 2026-10-10 10:48 | [38020195746](https://github.com/Omni16/Templar-Kernel-GKI-5.10/actions/runs/38020195746) | Templar-LinuxStable | 5.10.271 | Vanilla | off | off | `TemplarTestE-5.10.271-Templar-LinuxStable-Vanilla-20261010_1048.zip` | ✅ | Lan E/5: khong root + khong SUSFS = phai ra build thuan (khong root, khong SUSFS, khong Droid). |
| 2026-10-10 10:20 | [38020186645](https://github.com/Omni16/Templar-Kernel-GKI-5.10/actions/runs/38020186645) | Templar-LinuxStable | 5.10.271 | SukiSU-Ultra | on | off | — | ❌ | **Dung du kien.** Job `validate-inputs` chan SukiSU-Ultra + SUSFS: SukiSU-Ultra khong co `CONFIG_KSU_SUSFS`. Fail som, khong tieu tien build. |
| 2026-10-10 10:20 | [38020192607](https://github.com/Omni16/Templar-Kernel-GKI-5.10/actions/runs/38020192607) | Templar-LinuxStable | 5.10.271 | BakaSU + MultiMgr | on (`9892175`) | on | — | ❌ | **BUG THAT (khong phai loi hinh thuc).** Buoc `Verify Droidspaces fragment` fail: `CONFIG_NETFILTER_XT_TARGET_REJECT` **khong ton tai** trong cay 5.10 (da doc het `net/netfilter/Kconfig`, 1642 dong). Cay 5.10 tach REJECT theo he sinh vien, dung `IP_NF_TARGET_REJECT` + `IP6_NF_TARGET_REJECT`. Da sua. |
| 2026-10-10 10:17 | [38018240831](https://github.com/Omni16/Templar-Kernel-GKI-5.10/actions/runs/38018240831) | Templar-LinuxStable | 5.10.271 | ReSukiSU + MultiMgr | on (`9892175`) | on | `Templar-5.10.271-Templar-LinuxStable-ReSukiSU+SUSFS+MultiMgr+Droidspace-20261010_1017.zip` | ✅ | Build lai toan phan de xac nhan khong hong sau cac sua doi workflow. |
| 2026-10-10 10:11 | [38017753963](https://github.com/Omni16/Templar-Kernel-GKI-5.10/actions/runs/38017753963) | Templar-LinuxStable | 5.10.271 | ReSukiSU + MultiMgr | on (`9892175`) | on | `Templar-5.10.271-Templar-LinuxStable-ReSukiSU+SUSFS+MultiMgr+Droidspace-20261010_1011.zip` | ✅ | Build lai toan phan. |
| 2026-10-10 08:27 | [38011311814](https://github.com/Omni16/Templar-Kernel-GKI-5.10/actions/runs/38011311814) | Templar-LinuxStable | 5.10.269 | ReSukiSU + MultiMgr | on (`9892175`) | on | `Templar-5.10.269-Templar-LinuxStable-ReSukiSU+SUSFS+MultiMgr+Droidspace-20261010_0827.zip` | ✅ | Build đầu tiên có đủ root + SUSFS + Multi Manager + Droidspaces. Đã xác minh `.config` thực tế: `CONFIG_KSU=y`, `CONFIG_KSU_MULTI_MANAGER_SUPPORT=y`, `CONFIG_KSU_SUSFS=y`, `CONFIG_SYSVIPC/POSIX_MQUEUE/IPC_NS/PID_NS/USER_NS=y`. **Chưa flash lên máy** — lần đầu phải backup boot. |
| 2026-10-10 07:35 | [38007568048](https://github.com/Omni16/Templar-Kernel-GKI-5.10/actions/runs/38007568048) | Templar-LinuxStable | 5.10.271 | BakaSU *(bản cũ, đã gỡ)* | on | off | `Templar-5.10.271-Templar-LinuxStable-BakaSU+SUSFS-20261010_0735.zip` | ✅ | Build hồi quy xác nhận bước vendor `anykernel3/` + verify zip hoạt động end-to-end. Nguồn root sau này đã đổi sang ReSukiSU (= BakaSU đổi tên). |

---

## Việc cần làm khi ghi dòng mới

1. Build xong → tải artifact, `sha256sum -c *.sha256`, `unzip -p *.zip variant.prop`.
2. Chép **đúng** tên zip và phiên bản từ `variant.prop` vào bảng (không nhớ miệng).
3. Ghi mức xác minh của thiết bị vào cột Ghi chú (xem `DEVICES.md` mục 2).
4. Commit: `docs: ghi nhận build <ID> (<tên zip>)`.
