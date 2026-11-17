# Ltube

Tải bản mới nhất: [ltube.apk](https://github.com/Longlui/ltube/raw/main/ltube.apk)

Cài đặt trên Android:
1. Mở link trên bằng Chrome, chọn "Vẫn tải xuống" nếu được hỏi.
2. Mở file `ltube.apk`, cho phép cài ứng dụng không rõ nguồn gốc.
3. Nếu Play Protect cảnh báo, chọn "Vẫn cài đặt".

Phiên bản hiện tại: 0.2.0

## iPhone / iPad

Tải bản mới nhất: [ltube.ipa](https://github.com/Longlui/ltube/releases/download/ios-latest/ltube.ipa)

File chưa ký, cài bằng **Sideloadly** trên máy tính (miễn phí):
1. Cài Sideloadly từ trang chủ chính thức (sideloadly.io) trên máy tính Windows hoặc Mac.
   Trên Windows cần thêm iTunes và iCloud bản tải từ trang Apple (không dùng bản Microsoft Store).
2. Cắm iPhone vào máy tính bằng cáp, bấm "Tin cậy" trên iPhone nếu được hỏi.
3. Mở Sideloadly, kéo file `ltube.ipa` vào, nhập Apple ID (nên dùng Apple ID phụ), bấm **Start**.
4. Trên iPhone: Cài đặt → Cài đặt chung → VPN & Quản lý thiết bị → chọn Apple ID → **Tin cậy**.
5. iOS 16 trở lên: Cài đặt → Quyền riêng tư & Bảo mật → **Chế độ nhà phát triển** → bật, khởi động lại máy.

App ký bằng Apple ID miễn phí **hết hạn sau 7 ngày**: mở Sideloadly cài lại (hoặc bật tự gia hạn
qua Wi-Fi trong Sideloadly). Lịch sử xem không mất khi cài lại.

Bản iOS hiện chỉ có một mức chất lượng (thường 360p) và không tự cài được bản mới.
Mã nguồn bản iOS ở thư mục `ios/`, được GitHub Actions tự build mỗi lần thay đổi.

## Cấu hình từ xa

`config.json` được app đọc mỗi lần mở:
- `latest`: bản Android mới nhất. Tăng `versionCode` thì app trên máy người nhà tự báo "Có bản mới".
- `ios`: bản iOS mới nhất. Tăng `build` (khớp `CURRENT_PROJECT_VERSION` trong `ios/project.yml`) thì app iOS báo có bản mới.
- `topics`: các chip chủ đề trên trang chủ (tên hiển thị + từ khoá tìm kiếm).
- `trending`: các hàng thịnh hành, chọn trong `MUSIC`, `LIVE`, `GAMING`, `MOVIES`, `PODCASTS`.
