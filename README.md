# Ltube

Tải bản mới nhất: [ltube.apk](https://github.com/Longlui/ltube/raw/main/ltube.apk)

Cài đặt trên Android:
1. Mở link trên bằng Chrome, chọn "Vẫn tải xuống" nếu được hỏi.
2. Mở file `ltube.apk`, cho phép cài ứng dụng không rõ nguồn gốc.
3. Nếu Play Protect cảnh báo, chọn "Vẫn cài đặt".

Phiên bản hiện tại: 0.2.0

## Cấu hình từ xa

`config.json` được app đọc mỗi lần mở:
- `latest`: bản mới nhất. Tăng `versionCode` thì app trên máy người nhà tự báo "Có bản mới".
- `topics`: các chip chủ đề trên trang chủ (tên hiển thị + từ khoá tìm kiếm).
- `trending`: các hàng thịnh hành, chọn trong `MUSIC`, `LIVE`, `GAMING`, `MOVIES`, `PODCASTS`.
