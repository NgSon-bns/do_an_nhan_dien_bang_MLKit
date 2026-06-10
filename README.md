# AI Fitness Counter (Nhận diện & Đếm Bài Tập Thể Thao Thời Gian Thực)

Ứng dụng Flutter di động tích hợp trí tuệ nhân tạo (AI) giúp nhận diện tư thế, tự động đếm số lần và tính toán thời gian luyện tập của người dùng trực tiếp qua camera điện thoại. Ứng dụng cung cấp các đánh giá tư thế đúng/sai thời gian thực để giúp người dùng cải thiện hiệu quả bài tập và tránh chấn thương.

---

## 🌟 Tính Năng Nổi Bật

1. **Nhận diện & Đếm tự động 4 bài tập phổ biến**:
   - **Chống đẩy (Push-up)**: Đếm số lần tự động dựa trên góc khuỷu tay. Đánh giá lưng thẳng và độ sâu khi chống.
   - **Squat (Gánh đùi)**: Đếm số lần tự động khi hạ hông dưới song song đùi. Đánh giá độ nghiêng lưng và độ thẳng của ngực.
   - **Plank (Tấm ván)**: Tính thời gian giữ plank đúng tư thế chuẩn. Đồng hồ tự động tạm dừng nếu người dùng bị cong lưng hoặc nhô hông quá cao.
   - **Jumping Jack (Nhảy vung tay)**: Đếm số lần dựa vào nhịp nhảy dạng chân phối hợp vung tay cao qua đầu.
2. **Thuật toán Đánh giá Tư thế Đúng/Sai thời gian thực**:
   - Phân tích hình học góc khớp từ mô hình **Google ML Kit Pose Detection**.
   - Vẽ đè khung xương (Skeleton Overlay) trực tiếp lên camera:
     - **Màu xanh lá**: Khớp và các liên kết cơ thể thẳng hàng, chuẩn tư thế.
     - **Màu đỏ/cam + hiệu ứng phát sáng**: Vị trí khớp xương bị lệch hoặc sai tư thế.
   - Đưa ra phản hồi bằng văn bản hướng dẫn điều chỉnh cụ thể (ví dụ: *"Hạ hông xuống!"*, *"Giữ lưng thẳng!"*).
3. **Trải nghiệm Người dùng (UX) Premium**:
   - Giao diện tối sang trọng (Dark theme) với tông màu xanh Neon tương phản cao.
   - Các bảng thông số HUD phong cách **Glassmorphism** mờ nhòe chống che khuất tầm nhìn camera.
   - Hoạt ảnh rung lắc cảnh báo lỗi (shake animation) giúp thu hút sự chú ý khi người dùng đang tập.
   - Đo lượng calo tiêu hao và thống kê tổng thời gian tập luyện thực tế.
   - Hỗ trợ đổi Camera trước/sau tiện lợi để tự theo dõi (selfie).

---

## 📂 Kiến Trúc Thư Mục Dự Án

Mã nguồn được phân tách theo mô hình Clean Architecture thu gọn hướng tính năng (Feature-oriented):

```
lib/
├── core/
│   ├── theme/
│   │   └── app_theme.dart         # Cấu hình màu sắc, chữ viết và trang trí Glassmorphism
│   └── utils/
│       └── pose_math.dart         # Tiện ích toán học (Tính góc 3 điểm, khoảng cách, góc nghiêng)
├── models/
│   ├── exercise.dart              # Khai báo thông tin bài tập (mô tả, mục tiêu, độ khó)
│   └── workout_session.dart       # Quản lý trạng thái buổi tập (lượt đếm, thời gian, lượng calo, số lỗi)
├── services/
│   └── pose_detector_service.dart # Khởi tạo & xử lý hình ảnh camera bằng ML Kit Pose Detector
└── views/
    ├── exercise_list_screen.dart  # Trang chủ Dashboard chọn bài tập và xem thông số
    └── workout/
        ├── workout_screen.dart    # Phòng tập AI chính (Camera stream + Logic chấm điểm)
        └── widgets/
            ├── camera_stream_view.dart # Vẽ khung hình camera gốc, tự động căn tỷ lệ méo
            ├── pose_skeleton_painter.dart # Vẽ các khớp xương màu Xanh/Đỏ phản hồi tư thế
            └── workout_hud_panel.dart # Hiển thị HUD số lần, timer và cảnh báo rung khi sai tư thế
```

---

## 📐 Thuật Toán AI & Quy Tắc Đánh Giá Tư Thế

### 1. Chống đẩy (Push-up)
- **Đếm lần**: Sử dụng góc khuỷu tay phải hoặc trái.
  - Hạ thấp góc gối khuỷu tay $< 90^\circ$ $\rightarrow$ Trạng thái `DOWN`.
  - Đẩy thẳng tay góc khuỷu tay $> 155^\circ$ $\rightarrow$ Trạng thái `UP` (Đếm cộng thêm 1).
- **Kiểm tra lỗi**: Góc lưng nối `Vai - Hông - Đầu gối` phải thẳng từ $160^\circ$ đến $195^\circ$.
  - Góc $< 160^\circ$: Hông nhô cao $\rightarrow$ *"Hạ hông xuống, giữ lưng thẳng!"* (Tô đỏ nhóm khớp Lưng).
  - Góc $> 195^\circ$: Hông võng sâu xuống sàn $\rightarrow$ *"Nâng hông lên, gồng cơ bụng!"* (Tô đỏ nhóm khớp Lưng).

### 2. Squat (Gánh đùi)
- **Đếm lần**: Sử dụng góc gập đầu gối `Hông - Đầu gối - Cổ chân`.
  - Hạ sâu đùi góc gối $< 100^\circ$ $\rightarrow$ Trạng thái `DOWN`.
  - Đứng thẳng dậy góc gối $> 155^\circ$ $\rightarrow$ Trạng thái `UP` (Đếm cộng thêm 1).
- **Kiểm tra lỗi**:
  - Độ nghiêng của lưng so với trục đứng phải $< 45^\circ$. Nếu gập lưng quá nhiều $\rightarrow$ *"Giữ ngực cao và thẳng lưng lên!"*.

### 3. Plank (Tấm ván)
- **Cách đếm**: Tính thời gian giữ plank đúng tư thế (Hold duration). Đồng hồ chỉ tăng giây khi tư thế đạt chuẩn.
- **Kiểm tra lỗi**:
  - Đo độ lệch cơ thể so với phương nằm ngang $< 25^\circ$.
  - Đo góc lưng `Vai - Hông - Đầu gối` từ $165^\circ$ đến $195^\circ$.
  - Nếu góc lưng ngoài khoảng này $\rightarrow$ *"Nâng hông lên, gồng cơ bụng!"* hoặc *"Hạ hông xuống thấp một chút!"*. Đồng hồ đếm giây sẽ tự động tạm ngưng.

### 4. Jumping Jack
- **Đếm lần**: Phối hợp giữa khoảng cách cổ chân và vị trí cổ tay.
  - Nhảy rộng chân (Khoảng cách chân $> 1.55 \times$ chiều rộng vai) đồng thời 2 tay đưa cao hơn vai $\rightarrow$ Trạng thái `ACTIVE`.
  - Nhảy khép chân (Khoảng cách chân $< 1.25 \times$ chiều rộng vai) đồng thời tay hạ sát đùi $\rightarrow$ Trạng thái `NEUTRAL` (Đếm cộng thêm 1).
- **Kiểm tra lỗi**:
  - Nhảy rộng chân nhưng tay không vung cao $\rightarrow$ *"Vung tay cao hơn qua đầu!"*.
  - Tay vung cao nhưng chân khép chặt $\rightarrow$ *"Nhảy dạng chân rộng ra hơn!"*.

---

## 🛠️ Yêu Cầu Cài Đặt

1. **Flutter SDK**: Phiên bản `^3.11.4` hoặc mới hơn.
2. **Thiết bị**: Khuyến nghị chạy ứng dụng trên thiết bị di động thật (Android hoặc iOS) để camera hoạt động tốt và cảm biến nhận diện chính xác.
3. **Cấp quyền**: Cấp quyền truy cập Camera khi khởi chạy ứng dụng.

### Chạy ứng dụng locally:
```bash
# 1. Tải các thư viện phụ thuộc
flutter pub get

# 2. Khởi chạy dự án
flutter run
```
