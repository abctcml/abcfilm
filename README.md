# abcfilm

Ứng dụng Flutter Android xem thông tin phim với giao diện tối, màu nhấn đỏ và dữ liệu danh sách từ API NguonC.

## Tạo APK bằng GitHub trên điện thoại

1. Tạo repository GitHub mới tên `abcfilm`.
2. Tải lên **toàn bộ nội dung** trong file ZIP này (giải nén ZIP trước khi upload; không upload cả ZIP như một file).
3. Vào tab **Actions** của repository và bật Actions nếu GitHub yêu cầu.
4. Chọn workflow **Build Android APK** → **Run workflow**.
5. Khi workflow hoàn tất, mở lần chạy đó → **Artifacts** → tải `abcfilm-debug-apk`.
6. Giải nén artifact ZIP để lấy `app-debug.apk`.

## Chạy API

- Danh sách mới cập nhật: `https://phim.nguonc.com/api/films/phim-moi-cap-nhat?page=1`
- Chi tiết phim: `https://phim.nguonc.com/api/film/{slug}`

Danh sách dùng phân trang: ứng dụng tải trang tiếp theo khi cuộn gần cuối. Tính sẵn có và nội dung API phụ thuộc dịch vụ bên thứ ba.

## Phát video

Ứng dụng hiển thị các nguồn tập được API trả về. Nguồn `embed` được mở trong WebView; nguồn video trực tiếp `.m3u8` / `.mp4` được chuyển cho trình phát tương thích. Không phải mọi nguồn nhúng đều cho phép phát trong ứng dụng. Chỉ sử dụng nội dung bạn có quyền xem.
