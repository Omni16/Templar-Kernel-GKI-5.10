# DEVICES.md — Bảng thiết bị hỗ trợ

> ⚠️ **Zip hiện KHÔNG chặn flash nhầm máy.** Bản AK3 của repo này để
> `do.devicecheck=0` và `device.name1=` **trống** (xem `anykernel3/anykernel.sh`).
> Nghĩa là zip flash được trên bất kỳ máy GKI 5.10 tương thích nào — không có
> bước nào dừng bạn nếu nhầm máy. **Luôn backup boot trước khi flash** (script
> AK3 tự backup vào `/sdcard/Zyomi16Kernel_Backup(nguon du phong khi bootloop)`).

> 🔧 **Muốn bật chặn nhầm máy?** Điền `device.name1=` đúng giá trị của
> `ro.product.device` (xem mục 3), đổi `do.devicecheck=1`, rồi build lại.
> Chỉ điền khi đã xác minh trực tiếp trên máy thật.

## 1. Bảng thiết bị

Chỉ liệt kê máy **Snapdragon**. Biến thể vùng (bản India, bản Trung Quốc...)
**chưa xác minh nên chưa điền** — đừng tự thêm vào khi chưa đo.

| device.name1 | Tên thương mại | Chipset | Độ tin cậy | Trạng thái |
|---|---|---|---|---|
| `marble` | POCO F5 / Redmi Note 12 Turbo | Snapdragon 7+ Gen 2 | **C** (cao) | Nhánh AK3 mặc định là `marble`; đã build + flash được |
| `garnet` | Redmi Note 13 Pro 5G | *chưa đối chiếu* | **L** (thấp) | ⚠️ **Cần đo lại** — chưa xác minh sau thay đổi root/SUSFS/Droidspaces |
| `veux` | Redmi Note 12 Pro 5G | *chưa đối chiếu* | **L** (thấp) | ⚠️ **Cần đo lại** — chưa xác minh sau thay đổi root/SUSFS/Droidspaces |

Mức tin cậy:
- **C** — đã build, flash và boot thành công; root + SUSFS hoạt động.
- **L** — từng chạy được nhưng **chưa đo lại** với cấu hình hiện tại
  (ReSukiSU + SUSFS + Multi Manager + Droidspaces). Đừng phát hành chính thức.

## 2. Những gì một dòng "đã xác minh" bao gồm

Một thiết bị chỉ được đổi sang **C** khi cả 7 mục sau đều đạt trên máy thật:

1. `getprop ro.product.device` khớp đúng `device.name1`
2. `uname -r` = `5.10.x` (đúng dòng GKI của zip)
3. Flash zip → reboot → không bootloop, không mất dữ liệu
4. `uname -r` sau boot cho thấy phiên bản kernel mới
5. Root hoạt động (manager đọc được, `su` chạy được)
6. SUSFS hoạt động (lệnh kiểm tra SUSFS của manager báo bật đủ flag)
7. Droidspaces qua được màn hình *Settings → Requirements* của app

Nếu một mục nào đó fail, ghi rõ mục nào vào cột Ghi chú thay vì bỏ qua.

## 3. Cách lấy dữ liệu cho một hàng mới

```bash
adb shell getprop ro.product.device      # -> device.name1 (bắt buộc đúng)
adb shell getprop ro.product.model       # -> tên thương mại
adb shell uname -r                       # -> dòng kernel
adb shell getprop ro.build.version.release
# xác nhận đây là máy Snapdragon:
adb shell getprop ro.board.platform      # ví dụ: taro, kalama, ...
```

Đối chiếu `ro.product.device` **trực tiếp trên máy**, không tra cứu trên mạng
rồi điền — tên thương mại và codename hay bị lệch giữa các vùng.

## 4. Ghi chú chung

- Repo kernel (`Omni16/Templar-Kernel-GKI-5.10`) build từ `gki_defconfig`
  của nhánh được chọn, nên **mọi thiết bị dùng chung một Image**. Bảng này chỉ
  ghi mức độ xác minh, không chia nhánh build theo máy.
- KHI THÊM một thiết bị vào bảng: ghi mức **L** trước, nâng lên **C** chỉ sau
  khi đủ 7 mục ở mục 2.
- KHI ĐO LẠI một thiết bị (nhất là 2 dòng `garnet`, `veux`): chạy đủ 7 mục,
  cập nhật cột Độ tin cậy, và ghi một dòng vào `docs/build-history.md`.
