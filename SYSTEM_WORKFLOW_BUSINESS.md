# BẢN PHÂN TÍCH CHI TIẾT CẤU TRÚC NGHIỆP VỤ VÀ LUỒNG HOẠT ĐỘNG TOÀN DIỆN
## ĐỒ ÁN: HỆ THỐNG GIÁM SÁT BÀI TẬP THỂ THAO TRÊN ANDROID SỬ DỤNG NHẬN DIỆN TƯ THẾ CƠ THỂ (AI FITNESS COACH)

Tài liệu này trình bày chi tiết và chuyên sâu từng phân hệ nghiệp vụ, luồng xử lý dữ liệu và thuật toán vận hành của toàn bộ hệ thống ứng dụng AI Fitness Coach. Đây là tài liệu phục vụ giải trình chi tiết về kiến trúc phần mềm và giải thuật trong cuốn báo cáo tốt nghiệp và buổi bảo vệ trước Hội đồng.

---

## PHẦN I. CHI TIẾT NGHIỆP VỤ CỦA 5 PHÂN HỆ CỐT LÕI

Hệ thống được cấu trúc thành 5 nghiệp vụ chính hoạt động liên kết chặt chẽ từ phía máy khách (Flutter Client) lên phía máy chủ (Supabase Serverless Cloud):

```
       [ Client (Flutter App) ]                    [ Server (Supabase Backend) ]
 ┌───────────────────────────────────┐            ┌─────────────────────────────┐
 │ 1. AuthService (Auth, Profiles)   │ <────────> │ - Bảng profiles             │
 │ 2. AI Coach Survey (BMR/TDEE)     │            │                             │
 │ 3. Nutrition (Exclusion Filter)   │            │                             │
 │ 4. Real-time AI Camera (Pose)     │ <────────> │ - Bảng workout_history      │
 │ 5. CheckInService (Streak Cache)  │ <────────> │ - Bảng check_ins            │
 └───────────────────────────────────┘            └─────────────────────────────┘
```

---

### 1. Phân hệ nghiệp vụ Xác thực & Quản lý Hồ sơ (`AuthService`)
Nhiệm vụ chính là đảm bảo an toàn thông tin người dùng, lưu trữ các chỉ số thể chất cơ bản phục vụ cho việc tính toán dinh dưỡng và đề xuất bài tập.

#### A. Luồng nghiệp vụ đăng ký và kích hoạt OTP:
1.  **Đăng ký:** Người dùng nhập Email và Mật khẩu $\rightarrow$ Gọi hàm `signUp` gửi yêu cầu lên Supabase Auth $\rightarrow$ Supabase tự động gửi mã OTP 6 số về email của người dùng. Tài khoản ở trạng thái chờ kích hoạt.
2.  **Kích hoạt:** Người dùng nhập mã OTP $\rightarrow$ Gọi hàm `verifySignUpOtp` gửi kèm Email, Mã OTP và Họ tên $\rightarrow$ Xác thực thành công $\rightarrow$ Phiên đăng nhập được kích hoạt và Supabase tự động ghi nhận user.
3.  **Tạo hồ sơ gốc:** Ngay sau khi kích hoạt OTP thành công, app gọi hàm `createProfile` thực hiện câu lệnh chèn (Insert) bản ghi thông tin ban đầu vào bảng `profiles` chứa ID người dùng, email, và họ tên.

#### B. Cấu trúc chi tiết bảng cơ sở dữ liệu `profiles` trên Supabase:
*   `id` (`uuid`, Khóa chính PK): Liên kết 1-1 với ID trong bảng xác thực hệ thống `auth.users`.
*   `email` (`varchar`): Email đăng ký tài khoản.
*   `full_name` (`varchar`): Họ và tên của người dùng.
*   `gender` (`varchar`, Nullable): Giới tính (`male` / `female`).
*   `age` (`integer`, Nullable): Độ tuổi của người dùng.
*   `height` (`double precision`, Nullable): Chiều cao của người dùng (tính bằng cm).
*   `weight` (`double precision`, Nullable): Cân nặng của người dùng (tính bằng kg).
*   `goal` (`varchar`, Nullable): Mục tiêu thể chất (`Weight Loss` - Giảm cân, `Maintenance` - Giữ dáng, `Lean Bulking` - Tăng cơ nạc).
*   `ExcludedIngredients` (`text[]`, mảng văn bản): Danh sách các nhóm thực phẩm bị dị ứng hoặc kiêng ăn (ví dụ: `Thịt bò`, `Trứng`, `Thịt heo`...).
*   `created_at` (`timestamptz`): Thời gian khởi tạo hồ sơ (tự động lấy theo giờ máy chủ).

---

### 2. Phân hệ nghiệp vụ Khảo sát Thể chất HLV AI (`recommendation_screen.dart`)
Sử dụng các thông số thể chất được lưu trong hồ sơ người dùng để tính toán các chỉ số sức khỏe theo tiêu chuẩn Y học Thể thao quốc tế.

#### A. Thuật toán tính toán chỉ số sức khỏe:
*   **Chỉ số khối cơ thể (BMI):** 
    $$BMI = \frac{\text{Cân nặng (kg)}}{(\text{Chiều cao (m)})^2}$$
*   **Tỷ lệ trao đổi chất cơ bản (BMR):** Tính theo công thức **Mifflin-St Jeor** nổi tiếng:
    $$\text{BMR (Nam)} = 10 \times \text{Cân nặng (kg)} + 6.25 \times \text{Chiều cao (cm)} - 5 \times \text{Tuổi (năm)} + 5$$
    $$\text{BMR (Nữ)} = 10 \times \text{Cân nặng (kg)} + 6.25 \times \text{Chiều cao (cm)} - 5 \times \text{Tuổi (năm)} - 161$$
*   **Tổng năng lượng tiêu thụ hàng ngày (TDEE):** Tính dựa trên hệ số hoạt động thể chất (Activity Factor):
    $$\text{TDEE} = \text{BMR} \times \text{Activity Factor}$$
    *   Hệ số mặc định trong code được gán dựa trên ngưỡng BMR: Nếu người dùng có lượng cơ bắp lớn (BMR $> 1500$ kcal), hệ số hoạt động là $1.425$ (hoạt động vừa phải). Nếu BMR $\le 1500$ kcal, hệ số hoạt động là $1.375$ (hoạt động nhẹ nhàng).

#### B. Đề xuất lượng Calo nạp vào hàng ngày (`targetDailyCalories`) dựa trên Mục tiêu hình thể:
*   **Giảm cân (`Weight Loss`):** Tạo ra trạng thái thâm hụt calo nhẹ để đốt cháy mỡ thừa mà không làm suy nhược cơ thể (thâm hụt khoảng 15% calo so với mức TDEE):
    $$\text{targetDailyCalories} = \text{TDEE} \times 0.85$$
*   **Giữ dáng (`Maintenance`):** Giữ nguyên mức năng lượng nạp vào bằng mức tiêu thụ:
    $$\text{targetDailyCalories} = \text{TDEE}$$
*   **Tăng cơ nạc (`Lean Bulking`):** Tạo ra trạng thái thặng dư calo nhẹ để hỗ trợ tổng hợp sợi cơ mới khi tập kháng lực (thặng dư khoảng 10% calo so với mức TDEE):
    $$\text{targetDailyCalories} = \text{TDEE} \times 1.10$$
*   *Ngưỡng an toàn:* Để đảm bảo an toàn sinh học, nếu lượng calo mục tiêu tính ra nhỏ hơn mức BMR (mức năng lượng tối thiểu để duy trì sự sống), hệ thống sẽ tự động gán lượng calo mục tiêu bằng chính chỉ số BMR của người đó:
    $$\text{Nếu } \text{targetDailyCalories} < \text{BMR} \implies \text{targetDailyCalories} = \text{BMR}$$

---

### 3. Phân hệ nghiệp vụ Thực đơn Dinh dưỡng & Bộ lọc Dị ứng (`NutritionService`)
*   **Chức năng:** Tự động lên thực đơn gợi ý mẫu cho 7 ngày trong tuần dựa trên 3 nhóm chất đa lượng chính: **Tinh bột (Carbs)**, **Chất đạm (Protein)**, và **Chất béo (Fat)** với tỷ lệ calo nạp vào tiêu chuẩn là: Tinh bột 50%, Chất đạm 25%, Chất béo 25%.
*   **Bộ lọc dị ứng (Exclusion Filtering):** 
    *   Trong bảng `profiles`, người dùng đã chọn danh sách các thực phẩm bị dị ứng hoặc kiêng ăn (`ExcludedIngredients`).
    *   Hàm `getRecommendedMeals` trong code sẽ duyệt qua toàn bộ cơ sở dữ liệu các món ăn mẫu. Đối với mỗi món ăn, hệ thống kiểm tra danh sách nguyên liệu của món ăn đó (`ingredients`).
    *   **Logic loại bỏ:** Nếu có bất kỳ nguyên liệu nào trùng với danh sách dị ứng của người dùng, món ăn đó sẽ bị **loại bỏ hoàn toàn** khỏi thực đơn và thay thế bằng một món ăn thay thế an toàn khác.

---

### 4. Phân hệ nghiệp vụ Giám sát tập luyện AI Camera thời gian thực (`workout_screen.dart`)
*   **Chức năng:** Đây là phân hệ xử lý kỹ thuật phức tạp nhất, chuyển đổi hình ảnh động từ camera thành các điểm khớp xương và đưa ra phân tích tư thế.

#### A. Thuật toán tính toán Kế hoạch chia Set tập (`computeSetPlan`):
*   Thay vì bắt người dùng tập liên tục một mạch dẫn đến kiệt sức và sai tư thế, hệ thống tự động chia nhỏ mục tiêu thành các Set tập phù hợp:
    *   Lấy tổng số lần tập mục tiêu (`totalReps`) chia cho $4$.
    *   Nếu tỷ lệ này lớn hơn hoặc bằng $8$ lần tập/set $\rightarrow$ Chia làm **4 set**.
    *   Nếu nhỏ hơn $8$, số set tập sẽ bằng phần nguyên của phép chia `totalReps / 8`. (Ví dụ: Mục tiêu 15 lần sẽ được chia làm 2 set: Set 1 tập 8 lần, Set 2 tập 7 lần).
    *   Hệ thống tự động chèn khoảng thời gian **nghỉ ngơi 30 giây (Rest Timer)** giữa các set tập để người tập phục hồi nhịp tim.

#### B. Cơ chế đếm số lần tập sai tư thế (`incorrectPostureCount`):
*   Để tránh việc camera bị rung làm nhấp nháy liên tục và tăng biến đếm sai tư thế vô tội vạ, hệ thống áp dụng cơ chế lắng nghe **sự chuyển đổi trạng thái (State Transition Trigger)**:
    *   Hệ thống lưu lại trạng thái tư thế của khung hình trước đó (`_wasPostureCorrectLastFrame`).
    *   Chỉ khi trạng thái tư thế ở khung hình hiện tại chuyển từ **ĐÚNG** sang **SAI** (`!result.isPostureCorrect && _wasPostureCorrectLastFrame`), bộ đếm lỗi `incorrectPostureCount` mới được cộng thêm 1.
    *   Nhờ cơ chế này, người tập dù có giữ tư thế sai trong 5 giây (khoảng 150 khung ảnh camera) thì hệ thống cũng chỉ ghi nhận họ mắc **1 lỗi duy nhất** cho đến khi họ sửa lại tư thế đúng.

#### C. Cấu trúc bảng cơ sở dữ liệu `workout_history` trên Supabase:
*   `id` (`bigint`, Khóa chính PK tự tăng).
*   `user_id` (`uuid`, Khóa ngoại FK): Liên kết với bảng `profiles`.
*   `exercise_id` (`varchar`): ID của bài tập (`push_up`, `squat`, `plank`, `jumping_jack`, `walking_lunge`, `burpee`).
*   `reps_count` (`integer`): Tổng số lần tập đúng đã hoàn thành.
*   `duration_seconds` (`integer`): Tổng thời gian thực hiện buổi tập (tính bằng giây).
*   `calories_burned` (`double precision`): Tổng lượng calo tiêu hao của buổi tập.
*   `incorrect_postures` (`integer`): Tổng số lần mắc lỗi sai tư thế trong buổi tập.
*   `created_at` (`timestamptz`): Thời điểm hoàn thành bài tập (ghi nhận tự động theo múi giờ UTC trên server).

---

### 5. Phân hệ nghiệp vụ Điểm danh & Chuỗi chuyên cần Streak (`CheckInService`)
Tăng tương tác và duy trì động lực tập luyện bằng cách tính chuỗi ngày chuyên cần.

#### A. Thuật toán tính Streak chuyên cần liên tục (`_calculateStreak`):
*   Thuật toán nhận đầu vào là danh sách các ngày đã điểm danh của người dùng được sắp xếp theo thứ tự giảm dần (ngày gần nhất xếp đầu tiên):
    1.  **Bước 1 (Kiểm tra điều kiện duy trì chuỗi):** Lấy ngày hôm nay và ngày hôm qua. Nếu ngày điểm danh gần nhất trong danh sách không trùng với hôm nay và cũng không trùng với hôm qua $\rightarrow$ Chuỗi chuyên cần bị đứt $\rightarrow$ Trả về **`0`**.
    2.  **Bước 2 (Đếm chuỗi liên tục):** Khởi tạo `streak = 1`. Thiết lập một biến ngày so sánh `compareDate` bằng ngày gần nhất trong danh sách.
    3.  **Bước 3 (Duyệt vòng lặp về quá khứ):** Lặp qua các ngày tiếp theo trong danh sách. Lấy khoảng chênh lệch giữa ngày đang xét và ngày `compareDate`.
        *   Nếu khoảng chênh lệch đúng bằng **1 ngày** $\rightarrow$ Tăng biến `streak` lên 1, đồng thời cập nhật `compareDate` bằng ngày đang xét để tiếp tục so sánh tiếp.
        *   Nếu khoảng chênh lệch bằng **0 ngày** (trường hợp người tập tập nhiều lần trong cùng một ngày) $\rightarrow$ Bỏ qua không xử lý (không tăng streak nhưng không ngắt chuỗi).
        *   Nếu khoảng chênh lệch lớn hơn 1 ngày $\rightarrow$ Dừng vòng lặp và trả về giá trị `streak` hiện tại.

#### B. Cấu trúc bảng cơ sở dữ liệu `check_ins` trên Supabase:
*   `id` (`bigint`, Khóa chính PK tự tăng).
*   `user_id` (`uuid`, Khóa ngoại FK): Liên kết với bảng `profiles`.
*   `check_in_date` (`date`): Ngày điểm danh (định dạng `YYYY-MM-DD`). 
    *   *Ràng buộc đặc biệt:* Thiết lập ràng buộc duy nhất **Unique Constraint** trên cặp giá trị `(user_id, check_in_date)` để đảm bảo mỗi người dùng chỉ có duy nhất một bản ghi điểm danh cho mỗi ngày.
*   `created_at` (`timestamptz`): Thời điểm điểm danh tự động lấy giờ hệ thống server.

---

## PHẦN II. LUỒNG TRẢI NGHIỆM CHI TIẾT CỦA NGƯỜI DÙNG (USER JOURNEY FLOW)

Quy trình hoạt động của hệ thống từ khi người dùng mở ứng dụng lần đầu cho đến khi hoàn thành lịch trình được mô tả chi tiết qua từng bước:

```
[Mở App] ──> [Đăng nhập/Đăng ký] ──> [Khảo sát HLV AI] ──> [Dashboard]
                                                              │
                                                        (Chọn bài tập)
                                                              │
                                                              ▼
[Đồng bộ DB] <── [Hộp thoại kết quả] <── [Tập luyện] <── [Căn chỉnh Cam]
```

### Bước 1: Khởi động & Kiểm tra trạng thái xác thực
*   Ứng dụng khởi chạy. Lớp `main.dart` kiểm tra xem thiết bị đã có token phiên làm việc (Session Token) của Supabase hay chưa.
    *   Nếu **Chưa**: Chuyển hướng người dùng về màn hình đăng nhập `LoginScreen` hoặc tạo tài khoản `RegisterScreen`. Sau khi nhập OTP thành công sẽ chuyển sang màn hình khảo sát thể chất.
    *   Nếu **Rồi**: Đọc nhanh dữ liệu đã lưu trong bộ nhớ máy (SharedPreferences) và hiển thị tức thời màn hình Dashboard.

### Bước 2: Hiển thị Dashboard & Đề xuất dinh dưỡng
*   Giao diện Dashboard hiện thông tin chuỗi chuyên cần (Streak) và dải lịch 7 ngày trong tuần.
*   Người dùng bấm chuyển sang tab "HLV AI" $\rightarrow$ Hệ thống hiển thị chỉ số BMI, BMR, TDEE và gợi ý bữa ăn hàng ngày.
*   Nếu người dùng nhấn mở rộng (expand) thẻ bữa ăn $\rightarrow$ Xem chi tiết thực đơn, nguyên liệu. Nếu nhấn biểu tượng nút chuyển đổi bài tập, hệ thống sẽ đề xuất đổi bài tập khác phù hợp hơn.

### Bước 3: Chuẩn bị tập luyện & Căn chỉnh Camera
*   Người dùng chọn bài tập bất kỳ (ví dụ: Chống đẩy) $\rightarrow$ Hiện màn hình chuẩn bị.
*   Một Bottom Sheet trượt từ dưới lên, hiển thị chi tiết hình ảnh động minh họa tư thế tập đúng, các bước hướng dẫn động tác từ AI và cho phép người tập lựa chọn số lượng Reps mục tiêu (`25`, `50`, `75`... lần).
*   Người dùng nhấn "BẮT ĐẦU LUYỆN TẬP NGAY" $\rightarrow$ Hệ thống kích hoạt Camera trước và mở khung hình căn chỉnh:
    *   *Bài đứng (Squat/Lunge...):* Vẽ khung hình dọc chiếm 65% chiều rộng và 80% chiều cao màn hình.
    *   *Bài nằm (Plank/Push-up):* Vẽ khung hình nằm ngang chiếm 90% chiều rộng và 45% chiều cao màn hình.
    *   Hệ thống liên tục phát giọng nói cảnh báo: *"Hãy đứng lùi lại..."* hoặc *"Hãy nằm ngang xuống..."* cho đến khi toàn bộ các khớp cơ thể của người tập nằm gọn trong khung hình chữ nhật an toàn (đã tính dung sai biên 15%).

### Bước 4: Thực hiện bài tập & Nhận phản hồi thời gian thực
*   Khi người tập đã đứng đúng vị trí $\rightarrow$ Hệ thống đếm ngược $3, 2, 1$ giây bằng âm thanh lớn $\rightarrow$ Kích hoạt bộ ghi giờ tập và bắt đầu set tập chính.
*   Người tập thực hiện động tác trước camera:
    *   Nếu **Tập đúng**: Nền màn hình HUD hiển thị màu xanh lá cây, số Reps tăng lên 1, hệ thống phát âm thanh giọng nói khích lệ (*"Tốt lắm!"*, *"Tuyệt vời!"*).
    *   Nếu **Tập sai**: Màn hình HUD nhấp nháy viền màu đỏ, hệ thống phát cảnh báo lỗi cụ thể qua loa ngoài điện thoại (ví dụ: *"Hãy xuống sâu hơn nữa!"*, *"Thân người bị võng, hãy siết cơ bụng!"*), đồng thời tăng biến đếm lỗi tư thế.
*   Khi hoàn thành đủ số Reps của một set tập $\rightarrow$ Màn hình camera tự động làm mờ, hiện đếm ngược 30 giây nghỉ ngơi và phát âm thanh nhắc nhở người dùng hít thở sâu, uống nước. Hết 30 giây, tự động mở lại camera để vào set tiếp theo.

### Bước 5: Kết thúc bài tập & Đồng bộ dữ liệu
*   Sau khi hoàn thành tất cả các set tập $\rightarrow$ Hệ thống dừng đồng hồ đo thời gian, dừng xử lý camera và hiển thị Hộp thoại Kết quả tập luyện (Workout Results Dialog).
*   Hộp thoại hiển thị chi tiết: Tổng số Reps hoặc số giây đã tập, Tổng thời gian trôi qua, Lượng calo đã tiêu hao và Số lần tập sai tư thế.
*   Người dùng nhấn **"Lưu & Thoát"**:
    *   App gọi hàm `saveWorkoutResult` đẩy toàn bộ các chỉ số của buổi tập lên bảng `workout_history` trên Supabase.
    *   App gọi hàm `performCheckIn` thực hiện việc điểm danh ngày hôm nay trên bảng `check_ins` và cập nhật lại chuỗi ngày tập liên tục (Streak).
    *   Cập nhật đồng thời dữ liệu mới vào bộ nhớ đệm `SharedPreferences` dưới máy thiết bị để đảm bảo tính nhất quán dữ liệu ngoại tuyến.
    *   Chuyển hướng người dùng quay trở lại màn hình Dashboard chính.

---

## PHẦN III. CHI TIẾT LUỒNG XỬ LÝ ẢNH CAMERA THỜI GIAN THỰC (REAL-TIME PIPELINE)

Quy trình xử lý ảnh từ camera trước của thiết bị di động diễn ra liên tục theo mô hình Pipeline khép kín để tối ưu hóa hiệu năng:

```
[Khung ảnh Camera] ──> [Throttling (120ms)] ──> [Google ML Kit Pose]
                                                        │
                                                        ▼
[Render Skeleton] <── [Đếm Rep/Báo lỗi] <── [AlignmentHelper]
```

### Bước 1: Thu nhận và Lọc ảnh (Throttling)
*   Camera của thiết bị Android liên tục phát ra luồng ảnh thô (`CameraImage`).
*   Để tránh làm quá tải bộ vi xử lý và gây nóng máy, app áp dụng bộ lọc thời gian:
    `if (!_isProcessing && (now - _lastFrameTimeMs >= 120))`
    *   Chỉ khi điện thoại không bận xử lý khung hình cũ VÀ thời gian cách khung hình trước đó $\ge 120$ mili-giây (tối đa $\approx 8$ khung hình trong một giây), ảnh mới được chuyển đổi định dạng từ YUV sang định dạng ảnh đầu vào của ML Kit.

### Bước 2: Nhận diện khung xương bằng Google ML Kit
*   Mô hình AI trên thiết bị (On-device AI Model) của Google ML Kit thực hiện xử lý ảnh và trả về đối tượng `Pose` chứa danh sách 33 điểm mốc khớp xương (Landmarks) trên cơ thể với đầy đủ các tọa độ $(x, y, z)$ và độ tin cậy của điểm đó (`likelihood`).

### Bước 3: Ánh xạ tọa độ và Kiểm tra vùng an toàn (`AlignmentHelper`)
1.  **Ánh xạ tọa độ:** Chuyển đổi tọa độ khớp của ảnh về tọa độ pixel thực tế trên màn hình thông qua hàm `translateCoordinates`. Nếu dùng camera trước, tự động lật đối xứng trục $X$ để người dùng không bị ngược chiều chuyển động.
2.  **Kiểm tra độ tin cậy:** Hệ thống duyệt qua các khớp chính cần thiết cho bài tập (ví dụ: Vai, Hông, Gối, Cổ chân). Các khớp này phải có độ tin cậy `likelihood >= 0.45` thì mới tiến hành xử lý tiếp.
3.  **Kiểm tra Bounding Box:** 
    *   *Bài tập đứng:* Rộng = 65%, Cao = 80% màn hình. Khớp vai và hông của cả hai bên trái/phải phải nằm gọn trong vùng này (đã tính dung sai cộng thêm 15% diện tích biên).
    *   *Bài nằm ngang:* Rộng = 90%, Cao = 45% màn hình và dịch xuống sát đáy. Chỉ cần vai và hông của 1 trong 2 bên (trái hoặc phải) hiển thị và nằm gọn trong vùng này là đạt yêu cầu.
4.  Nếu người tập đứng ngoài vùng an toàn $\rightarrow$ Ngắt trạng thái tập, chuyển biến `isPostureCorrect = false`, hiện cảnh báo nhắc nhở di chuyển lùi lại/nằm xuống.

### Bước 4: Đánh giá bằng máy trạng thái (Exercise Evaluators)
Nếu người tập đứng đúng vị trí, dữ liệu khung xương được chuyển qua bộ đánh giá tư thế của riêng bài tập đó để chạy máy trạng thái (Xem chi tiết thuật toán của từng bài tập tại **Phần IV**).

### Bước 5: Render đồ họa hiển thị (Canvas Painting)
*   Khung xương skeleton của người tập được vẽ trực tiếp đè lên luồng video camera theo thời gian thực: các đường xương nối sẽ đổi màu: màu **Xanh lá cây** nếu góc khớp đạt chuẩn đúng tư thế, hoặc màu **Đỏ** tại bộ phận bị sai tư thế (ví dụ: đường nối vai-hông bị đỏ nếu lưng bị gù).
*   Đồng thời, cập nhật các chỉ số Reps, Calo và đồng hồ bấm giờ lên bảng giao diện điều khiển (HUD Panel) để người tập dễ dàng theo dõi kết quả.

---

## PHẦN IV. THÔNG SỐ GÓC VÀ MÁY TRẠNG THÁI CỦA 6 BÀI TẬP AI CAMERA

Bộ não phân tích động tác của ứng dụng bao gồm 6 lớp Evaluator thực thi thuật toán máy trạng thái (State Machine) và đo góc lượng giác học:

---

### 1. Squat (Gánh đùi)
*   **Tham số góc đo:** Góc gập khớp gối (Knee Joint Angle) và góc nghiêng lưng so với phương thẳng đứng (Back Lean Angle).
*   **Trạng thái máy (States):**
    *   `BurpeeState.stand` (Đứng thẳng): Góc đầu gối $> 155^\circ$.
    *   `BurpeeState.squat` (Hạ hông xuống sâu): Góc đầu gối $< 100^\circ$.
*   **Cơ chế đếm Rep:** Khi người dùng đứng gập gối xuống dưới $100^\circ$ (chuyển sang trạng thái gập) rồi đứng thẳng dậy duỗi thẳng chân vượt quá $155^\circ$ $\rightarrow$ Đếm 1 rep.
*   **Đánh giá tư thế lỗi (Lỗi gù/khòm lưng):**
    *   Nếu góc nghiêng lưng so với phương thẳng đứng $> 45^\circ$ trong khi đang gập gối $\rightarrow$ HUD nhấp nháy đỏ và cảnh báo: *"Hãy giữ ngực cao và thẳng lưng"*.

---

### 2. Chống đẩy (Push-Up)
*   **Tham số góc đo:** Góc khớp khuỷu tay (Elbow Angle) và độ thẳng hàng của đường nối Vai – Hông – Gối (Back/Torso Alignment Angle).
*   **Trạng thái máy (States):**
    *   `UP` (Thẳng tay): Góc khuỷu tay $> 150^\circ$.
    *   `DOWN` (Hạ ngực sát sàn): Góc khuỷu tay $< 110^\circ$.
*   **Cơ chế đếm Rep:** Khi khuỷu tay gập dưới $110^\circ$ (xuống sâu) rồi đẩy thẳng tay mở góc khuỷu tay vượt quá $150^\circ$ $\rightarrow$ Đếm 1 rep.
*   **Đánh giá tư thế lỗi:**
    *   *Kiểm tra và chuẩn hóa độ sâu theo tỷ lệ cơ thể:* Đo độ dịch chuyển dọc của vai từ mốc thẳng tay đến điểm hạ người thấp nhất. Chia độ dịch chuyển này cho **Độ dài thân người (khoảng cách Vai - Hông)** để có tỷ lệ chuẩn hóa cơ thể:
        $$\text{Tỷ lệ dịch chuyển} = \frac{\text{Vai Y hiện tại} - \text{Vai Y thẳng tay}}{\text{Độ dài thân người (Vai - Hông)}}$$
        Nếu tỷ lệ này $< 0.10$ (tức là độ sâu hạ người ít hơn 10% chiều dài thân người) $\rightarrow$ Cảnh báo: *"Hãy xuống sâu hơn nữa!"* và rep tập đó không được đếm.
    *   *Lỗi võng lưng / nhô mông:* Góc nối giữa Vai – Hông – Gối phải thẳng (trong khoảng $[152^\circ, 200^\circ]$). Nếu góc này nằm ngoài khoảng này $\rightarrow$ Cảnh báo: *"Lần tập không được tính do sai tư thế!"*.

---

### 3. Plank (Tấm ván)
*   **Tham số góc đo:** Góc nghiêng cơ thể so với sàn nhà và góc thẳng hàng Vai – Hông – Cổ chân.
*   **Cơ chế đo thời gian:** Không đếm số lần tập. Đồng hồ đếm thời gian chỉ tích lũy khi giữ tư thế Plank chuẩn.
*   **Điều kiện bắt đầu Plank:** Đường thẳng nối Vai – Cổ chân nghiêng so với mặt đất nằm ngang một góc $\le 40^\circ$. Nếu lớn hơn $40^\circ$, cảnh báo: *"Hãy nằm ngang xuống để bắt đầu tập Plank!"*.
*   **Đánh giá tư thế lỗi:**
    *   Góc nối Vai – Hông – Cổ chân phải thẳng $\ge 165^\circ$.
    *   *Lỗi cao hông:* Hông nhô cao vượt đường thẳng lý tưởng Vai - Cổ chân $> 0.04$ đơn vị $\rightarrow$ Cảnh báo: *"Hông quá cao, hãy hạ thấp hông xuống!"*.
    *   *Lỗi võng lưng:* Hông võng thấp dưới đường thẳng lý tưởng $> 0.04$ đơn vị $\rightarrow$ Cảnh báo: *"Thân người bị võng, hãy siết cơ bụng nâng hông lên!"*.
    *   *Bộ lọc nhiễu:* Lỗi phải kéo dài liên tục quá 10 khung hình để tránh báo lỗi nhấp nháy do camera rung.

---

### 4. Jumping Jack (Nhảy dang tay chân)
*   **Tham số góc đo:** Tỷ lệ dạng chân `feetRatio` (Khoảng cách 2 cổ chân / Chiều rộng 2 vai) và vị trí cổ tay so với vai.
*   **Trạng thái máy (States):**
    *   `NEUTRAL` (Khép tay chân): Tỷ lệ `feetRatio` $< 1.15$ và hai tay hạ thấp dưới vai một khoảng cách tối thiểu bằng 40% chiều rộng vai.
    *   `ACTIVE` (Dạng rộng tay chân): Tỷ lệ `feetRatio` $> 1.45$ và hai tay giơ cao qua vai (Cổ tay Y < Vai Y).
*   **Cơ chế đếm Rep:** Nhảy dạng chân và giơ tay qua đầu (chuyển sang `ACTIVE`) rồi thu chân khép lại hạ tay về vị trí cũ (`NEUTRAL`) $\rightarrow$ Đếm 1 rep.
*   **Đánh giá tư thế lỗi:**
    *   Dạng chân nhưng không vung tay qua đầu $\rightarrow$ Cảnh báo: *"Vung tay cao hơn qua đầu!"*.
    *   Vung tay cao nhưng chân không nhảy dạng rộng $\rightarrow$ Cảnh báo: *"Nhảy dạng chân rộng ra hơn!"*.

---

### 5. Walking Lunge (Bước chùng chân)
*   **Tham số góc đo:** Góc gập của cả hai khớp gối trái và phải (Knee Angles) và góc nghiêng lưng.
*   **Trạng thái máy (States):**
    *   `stand` (Đứng thẳng): Cả hai góc gối duỗi thẳng $> 150^\circ$.
    *   `lunge` (Tấn xuống): Cả hai góc gối đều gập gối xuống dưới $< 110^\circ$ (góc gối chân trước song song sàn $\approx 90^\circ$, gối chân sau hướng xuống sàn $\approx 90^\circ$).
*   **Cơ chế đếm Rep:** Bước tấn gập gối dưới $110^\circ$ rồi đứng dậy duỗi thẳng chân vượt quá $150^\circ$ $\rightarrow$ Đếm 1 rep.
*   **Đánh giá tư thế lỗi (Lỗi khom lưng):**
    *   Góc lưng nghiêng so với phương thẳng đứng $> 20^\circ$ $\rightarrow$ Không đếm rep, cảnh báo: *"Giữ ngực cao và thẳng lưng lên!"*.

---

### 6. Burpee (Hít đất bật nhảy phức hợp)
*   **Tham số góc đo:** Kết hợp liên hoàn góc hông, góc gối, góc dốc thân người và vị trí cổ tay.
*   **Trạng thái máy (States):**
    1.  `stand` (Đứng thẳng): Góc gối và hông đều duỗi thẳng.
    2.  `squat` (Ngồi xổm): Góc hông gập sâu $< 115^\circ$.
    3.  `plank` (Nằm chống đẩy): Thân người nằm ngang (Góc dốc thân so với sàn $< 35^\circ$), góc hông $> 135^\circ$, gối duỗi thẳng $> 120^\circ$.
    4.  `recover` (Thu chân về xổm): Thu chân nhanh làm góc hông gập lại $< 115^\circ$, góc dốc thân quay lại $> 20^\circ$.
    5.  `jump` (Bật nhảy): Bật nhảy cao lên không trung (Trục Y của hông nhấc cao vượt mốc đứng thẳng một khoảng bằng 3% chiều dài thân người) đồng thời vung 2 tay qua đầu.
*   **Cơ chế đếm Rep:** Đi qua đầy đủ chuỗi 5 trạng thái trơn tru $\rightarrow$ Trở về `stand` $\rightarrow$ Cộng 1 rep.
*   **Cơ chế dự phòng (Global Recovery):** Nếu camera mất dấu khớp do chuyển động quá nhanh, chỉ cần người tập đã từng chạm xuống đất làm `plank`, khi họ đứng thẳng dậy bật nhảy cao giơ tay qua đầu $\rightarrow$ Thuật toán tự động hoàn tất chu kỳ đếm 1 rep để tránh kẹt máy trạng thái.
*   **Đánh giá tư thế lỗi (Lỗi cong lưng khi Plank):**
    *   Trong pha Plank, nếu mông nhô cao hoặc thân người bị gấp khúc (góc dốc thân so với phương ngang nằm trong khoảng $[25^\circ, 65^\circ]$ quá 8 khung hình liên tiếp) $\rightarrow$ Cảnh báo: *"Hãy giữ lưng và hông thẳng song song mặt sàn (Plank)!"*.
