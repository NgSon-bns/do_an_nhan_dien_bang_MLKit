# CẨM NANG ÔN TẬP VẤN ĐÁP LUẬN VĂN TỐT NGHIỆP
## Đề tài: Ứng dụng Hỗ trợ Tập luyện Thể thao AI Fitness Coach tích hợp Nhận diện Tư thế và Backend Serverless

Tài liệu này được biên soạn chi tiết nhằm giúp bạn chuẩn bị tốt nhất cho buổi bảo vệ luận văn (vấn đáp) trước Hội đồng. Nội dung được đúc kết từ toàn bộ cấu trúc và các chỉnh sửa kỹ thuật mới nhất trong báo cáo luận văn của bạn.

---

## MỤC LỤC
1. [CÁC CÂU HỎI TỔNG QUAN & ĐỀ TÀI](#1-các-câu-hỏi-tổng-quan--đề-tài)
2. [CÁC CÂU HỎI VỀ THUẬT TOÁN AI & NHẬN DIỆN TƯ THẾ (GOOGLE ML KIT)](#2-các-câu-hỏi-về-thuật-toán-ai--nhận-diện-tư-thế-google-ml-kit)
3. [CÁC CÂU HỎI VỀ CƠ SỞ DỮ LIỆU & BẢO MẬT (SUPABASE RLS)](#3-các-câu-hỏi-về-cơ-sở-dữ-liệu--bảo-mật-supabase-rls)
4. [CÁC CÂU HỎI VỀ KIẾN TRÚC ĐỒNG BỘ NGOẠI TUYẾN (OFFLINE-FIRST SYNC)](#4-các-câu-hỏi-về-kiến-trúc-đồng-bộ-ngoại-tuyến-offline-first-sync)
5. [CÁC CÂU HỎI VỀ QUYỀN RIÊNG TƯ & CAMERA STREAM](#5-các-câu-hỏi-về-quyền-riêng-tư--camera-stream)
6. [CÁC CÂU HỎI VỀ KIỂM THỬ & THỰC NGHIỆM (CHƯƠNG 4)](#6-các-câu-hỏi-về-kiểm-thử--thực-nghiệm-chương-4)

---

## 1. CÁC CÂU HỎI TỔNG QUAN & ĐỀ TÀI

### HĐ Hỏi: Tại sao em lại chọn đề tài này? Điểm mới/sự khác biệt của ứng dụng này so với các ứng dụng thể thao khác trên thị trường là gì?
* **Trả lời:** 
  Các ứng dụng thể thao hiện nay đa số chỉ dừng lại ở việc phát video hướng dẫn tĩnh hoặc đếm thời gian thô sơ, người tập không biết mình tập đúng hay sai tư thế, dễ dẫn đến chấn thương gối, lưng hoặc bả vai. 
  Điểm mới và khác biệt của ứng dụng của em là:
  1. **Nhận diện và sửa sai tư thế thời gian thực:** Ứng dụng sử dụng camera điện thoại và AI để nhận diện khung xương 3D và đưa ra phản hồi bằng giọng nói tiếng Việt và chỉ thị màu trực quan ngay khi người tập làm sai.
  2. **Xử lý hoàn toàn ngoại tuyến (On-device processing):** Không cần gửi video/hình ảnh lên server, giúp bảo vệ quyền riêng tư tuyệt đối cho không gian tập luyện của người dùng và triệt tiêu hoàn toàn độ trễ mạng.
  3. **Độ chính xác cao nhờ bộ lọc nâng cao:** Áp dụng các bộ lọc temporal filter (Moving Average, Debounce, Majority Vote) và chuẩn hóa cơ thể để tránh sai số do khoảng cách và ngoại cảnh.

### HĐ Hỏi: Phạm vi nghiên cứu và kiểm thử thực tế của đề tài này là gì?
* **Trả lời:** 
  * **Về bài tập:** Hệ thống hỗ trợ nhận diện và đếm tự động 5 bài tập cốt lõi: Squat (Gánh đùi), Push-up (Chống đẩy), Plank (Tấm ván), Jumping Jack (Nhảy tách tay chân), Walking Lunge (Chùng chân bước đi) và bài tập phức hợp Burpee.
  * **Về nền tảng:** Ứng dụng được xây dựng bằng Flutter và được giới hạn phạm vi kiểm thử thực tế trên hệ điều hành **Android** (sử dụng các thiết bị thật có cấu hình khác nhau để đo đạc độ trễ và độ chính xác dưới các điều kiện ánh sáng, góc độ, khoảng cách).

---

## 2. CÁC CÂU HỎI VỀ THUẬT TOÁN AI & NHẬN DIỆN TƯ THẾ (GOOGLE ML KIT)

### HĐ Hỏi: Em sử dụng mô hình học máy nào để nhận diện tư thế? Hãy mô tả cơ chế hoạt động của mô hình đó?
* **Trả lời:** 
  Em tích hợp SDK **Google ML Kit Pose Detection**, hoạt động dựa trên mô hình mạng nơ-ron sâu **BlazePose** [9]. 
  * **Đầu vào:** Luồng ảnh camera thời gian thực (ImageStream).
  * **Đầu ra:** Tọa độ 3 chiều $(x, y, z)$ cùng điểm số tin cậy (visibility score) của **33 điểm mốc khớp xương** (landmarks) trên toàn bộ cơ thể theo chuẩn của MediaPipe.
  * Trong đó, trục $x, y$ biểu thị tọa độ pixel chuẩn hóa trên khung hình, còn trục $z$ biểu thị độ sâu tương đối của khớp xương so với điểm hông của người tập (giá trị $z$ càng nhỏ nghĩa là khớp càng gần camera hơn).

### HĐ Hỏi: Điểm số tin cậy (visibility score) là gì và em đã áp dụng nó như thế nào để xử lý dữ liệu?
* **Trả lời:** 
  Visibility score là một giá trị số thực nằm trong khoảng $[0.0, 1.0]$ do mô hình BlazePose trả về cho từng điểm mốc, thể hiện xác suất điểm khớp đó không bị che khuất và hiển thị rõ ràng trong khung hình.
  * **Ứng dụng:** Để tránh hiện tượng rung nhiễu hoặc tính toán góc sai lệch khi một bộ phận cơ thể bị che khuất (do góc quay hoặc vật cản), hệ thống của em thiết lập ngưỡng **`visibility >= 0.50`**.
  * Chỉ các điểm khớp liên quan đạt điểm tin cậy trên $0.50$ mới được đưa vào công thức lượng hình tính góc. Các trường hợp dưới ngưỡng sẽ bị bỏ qua hoặc áp dụng bộ lọc nội suy (linear interpolation) lấy tọa độ từ khung hình trước đó để giữ bộ xương ổn định.

### HĐ Hỏi: Công thức toán học nào được dùng để tính toán các góc khớp xương từ tọa độ 3D?
* **Trả lời:** 
  Góc giữa ba điểm khớp $A$ (khớp đỉnh), $B$ (khớp trung tâm/bản lề), và $C$ (khớp cuối) được tính toán bằng cách thiết lập hai vectơ $\vec{u} = \vec{BA}$ và $\vec{v} = \vec{BC}$.
  Sau đó, áp dụng công thức tích vô hướng trong không gian 3 chiều:
  $$\cos \theta = \frac{\vec{u} \cdot \vec{v}}{\|\vec{u}\| \|\vec{v}\|} = \frac{x_u x_v + y_u y_v + z_u z_v}{\sqrt{x_u^2 + y_u^2 + z_u^2} \sqrt{x_v^2 + y_v^2 + z_v^2}}$$
  Góc $\theta$ (đơn vị radian) sau đó được chuyển đổi sang độ (degree) bằng công thức $\theta_{deg} = \theta \times \frac{180}{\pi}$ để đưa vào các máy trạng thái.

### HĐ Hỏi: Hãy giải thích cách em giải quyết hạn chế của việc sử dụng "ngưỡng góc cứng cố định" khi người dùng đứng xa/gần hoặc nghiêng người?
* **Trả lời:** 
  Nếu dùng ngưỡng cứng cố định sẽ dễ gây sai lệch do tỷ lệ cơ thể khác nhau hoặc vị trí xa gần của camera. Em đã giải quyết bằng hai kỹ thuật:
  1. **Chuẩn hóa kích thước cơ thể tương đối (Body Normalization):** Thay vì đo khoảng cách tuyệt đối bằng số pixel, hệ thống tính toán tỷ lệ tương đối giữa các khớp (ví dụ: chia khoảng cách giữa hai cổ chân cho chiều rộng bả vai hiện tại). Tỷ lệ này không thay đổi cho dù người dùng đứng xa hay gần camera.
  2. **Nội suy góc 3D:** Công thức góc của em sử dụng cả tọa độ chiều sâu $z$ của BlazePose [13], giúp tính góc chính xác ngay cả khi người tập đứng chéo góc $30^\circ - 45^\circ$ so với camera, thay vì chỉ hoạt động ở mặt phẳng 2D chính diện.

### HĐ Hỏi: Em đã áp dụng các bộ lọc thời gian (Temporal Filters) nào để khử nhiễu tín hiệu camera (jitter, motion blur)?
* **Trả lời:** 
  Do camera điện thoại có thể bị rung hoặc mờ hình khi người tập nhảy nhanh, em áp dụng 3 bộ lọc thời gian:
  1. **Trung bình động (Moving Average):** Lọc mượt tọa độ khớp xương bằng cách lấy trung bình cộng tọa độ trên một cửa sổ trượt gồm 5 khung hình liên tiếp.
  2. **Debounce (Khử nảy):** Bỏ qua các chuyển động dao động trạng thái cực ngắn (dưới 150ms). Người dùng phải giữ trạng thái tư thế ổn định trên 150ms mới ghi nhận chuyển đổi.
  3. **Đa số phiếu (Majority Vote):** Trạng thái tư thế phải xuất hiện liên tục trong tối thiểu $N$ khung hình (ví dụ: 3/5 khung hình gần nhất) thì máy trạng thái mới chấp nhận chuyển đổi, giúp triệt tiêu rung nhiễu (jitter) xung quanh ngưỡng ranh giới đếm rep.

### HĐ Hỏi: Hãy trình bày thuật toán Máy trạng thái (State Machine) đếm reps bài tập Squat và Push-up?
* **Trả lời:** 
  * **Squat:** Máy trạng thái có 2 trạng thái chính:
    * Trạng thái `STAND` (Đứng thẳng): Góc gối $> 155^\circ$.
    * Trạng thái `DOWN` (Hạ hông chuẩn): Góc gối $< 100^\circ$. Khi gối gập dưới $100^\circ$, hệ thống chuyển sang trạng thái `DOWN`. Khi người tập đứng thẳng dậy vượt quá $155^\circ$, hệ thống chuyển về `STAND` và cộng 1 rep.
    * *Cảnh báo lỗi:* Nếu góc lưng (độ nghiêng so với phương thẳng đứng) $> 45^\circ$ khi đang ở trạng thái gập gối, hệ thống cảnh báo *"Hãy giữ ngực cao và thẳng lưng"*.
  * **Push-up:** 
    * Trạng thái `UP` (Thẳng tay): Góc khuỷu tay $> 155^\circ$.
    * Trạng thái `DOWN` (Hạ ngực sâu): Góc khuỷu tay $< 90^\circ$.
    * Khi khuỷu tay gập dưới $90^\circ$, chuyển sang `DOWN`. Khi đẩy thẳng tay vượt quá $155^\circ$, chuyển về `UP` và cộng 1 rep.
    * *Cảnh báo lỗi:* Góc nối giữa `Vai - Hông - Gối` phải thẳng (nằm trong khoảng $160^\circ - 195^\circ$). Nếu góc này $< 160^\circ$ (võng hông) hoặc $> 195^\circ$ (nhô hông), hệ thống báo lỗi sai lưng.

### HĐ Hỏi: Bài tập phức hợp Burpee hoạt động như thế nào? Em đã thiết lập cơ chế kiểm soát thời gian chuyển đổi và hạn chế của nó ra sao?
* **Trả lời:** 
  Bài tập Burpee được thiết kế dưới dạng máy trạng thái tuần tự gồm 6 trạng thái liên tục:
  $$\text{STAND} \rightarrow \text{SQUAT} \rightarrow \text{PLANK} \rightarrow \text{PUSHUP} \rightarrow \text{PLANK} \rightarrow \text{SQUAT} \rightarrow \text{STAND}$$
  Để đảm bảo người dùng tập luyện đúng nhịp và an toàn, em đã tích hợp:
  * **State Transition Timeout (3.5 giây):** Người tập phải chuyển tiếp giữa các pha trong vòng tối đa 3.5 giây. Nếu quá 3.5 giây mà không đạt pha kế tiếp, máy trạng thái sẽ tự động reset về trạng thái STAND ban đầu.
  * **Thời gian pha tối thiểu (Min Phase Duration):** Pha Plank phải được duy trì tối thiểu 0.5 giây để tránh việc người dùng nhảy lướt nhanh sai tư thế.
  * **Cơ chế Reset mất dấu (2.0 giây):** Nếu camera mất dấu toàn bộ cơ thể người tập quá 2.0 giây, hệ thống tự động đưa máy trạng thái về STAND để tránh lỗi đếm sai khi người dùng quay lại khung hình.

---

## 3. CÁC CÂU HỎI VỀ CƠ SỞ DỮ LIỆU & BẢO MẬT (SUPABASE RLS)

### HĐ Hỏi: Tại sao em lại chọn Supabase làm Cloud Backend thay vì Firebase?
* **Trả lời:** 
  1. **Hệ quản trị CSDL quan hệ PostgreSQL mạnh mẽ:** Supabase sử dụng PostgreSQL, hỗ trợ các mối quan hệ khóa ngoại chặt chẽ, các câu lệnh truy vấn SQL phức tạp, tối ưu hơn Firebase Firestore (NoSQL) cho các dữ liệu có tính liên kết cao như Hồ sơ người dùng $\leftrightarrow$ Lịch sử tập luyện.
  2. **Bảo mật cấp hàng (Row-Level Security - RLS) phía máy chủ:** Cho phép cấu hình phân quyền bảo mật trực tiếp trên PostgreSQL, đảm bảo dữ liệu được cô lập an toàn ở tầng sâu nhất.
  3. **Hỗ trợ thời gian thực (Real-time) và Serverless:** Giúp ứng dụng đồng bộ dữ liệu nhanh chóng, giảm thiểu tối đa chi phí vận hành server trung gian.

### HĐ Hỏi: Row-Level Security (RLS) là gì? Hãy trình bày cụ thể chính sách RLS em đã thiết lập cho từng bảng?
* **Trả lời:** 
  RLS là cơ chế bảo mật của PostgreSQL, cho phép kiểm soát quyền truy cập (SELECT/INSERT/UPDATE/DELETE) đến từng dòng dữ liệu trong bảng dựa trên danh tính (User ID) của người dùng gửi yêu cầu.
  Em đã bật RLS và cấu hình chính sách cụ thể cho các bảng như sau (Mã SQL được đính kèm ở Phụ lục báo cáo):
  * **Bảng `profiles` (Hồ sơ):**
    ```sql
    CREATE POLICY "Allow users to view own profile" ON profiles FOR SELECT USING (auth.uid() = id);
    CREATE POLICY "Allow users to update own profile" ON profiles FOR UPDATE USING (auth.uid() = id);
    ```
    *(Mỗi tài khoản chỉ xem/sửa duy nhất hồ sơ cá nhân của chính mình).*
  * **Bảng `workout_history` (Lịch sử tập luyện) và `check_ins` (Điểm danh):**
    ```sql
    CREATE POLICY "Allow users to view own workouts" ON workout_history FOR SELECT USING (auth.uid() = user_id);
    CREATE POLICY "Allow users to insert own workouts" ON workout_history FOR INSERT WITH CHECK (auth.uid() = user_id);
    ```
    *(Chỉ cho phép đọc/ghi dữ liệu lịch sử nếu User ID của dòng bản ghi trùng khớp với UID của tài khoản đăng nhập).*

### HĐ Hỏi: RLS có ngăn chặn hoàn toàn các lỗ hổng bảo mật không? Nếu lộ API Key của Supabase thì hệ thống có bị hack dữ liệu không?
* **Trả lời:** 
  * **RLS không phải là vạn năng:** RLS chỉ bảo vệ dữ liệu hiệu quả nếu các chính sách Policy được cấu hình đúng đắn và bao phủ toàn bộ các hành động. Nếu nhà phát triển viết sai điều kiện hoặc quên bật RLS trên một bảng nào đó, dữ liệu vẫn có thể bị rò rỉ. Ngoài ra, hệ thống vẫn có nguy cơ bị lộ token phiên đăng nhập nếu thiết bị client lưu trữ không an toàn.
  * **Về API Key:** Supabase có hai loại khóa: `anon key` (khóa công khai dành cho client) và `service-role key` (khóa quản trị tối cao, bypass qua mọi RLS). 
  * Trong ứng dụng client di động, em **chỉ tích hợp khóa `anon key`**. Do đó, cho dù kẻ tấn công có dịch ngược ứng dụng và lấy được `anon key`, mọi yêu cầu truy vấn của chúng gửi lên Supabase vẫn bắt buộc phải đi qua cơ chế kiểm soát RLS của database. Kẻ tấn công chỉ đọc được dữ liệu của chính tài khoản mà chúng đăng nhập, hoàn toàn không thể đọc hay sửa đổi dữ liệu của người dùng khác. Khóa `service-role key` được giữ bí mật tuyệt đối trên máy chủ và không bao giờ được gửi kèm ứng dụng client.

### HĐ Hỏi: Phiên đăng nhập (Session Token) được lưu trữ như thế nào trên thiết bị Android?
* **Trả lời:** 
  On-device, token xác thực phiên đăng nhập trên hệ điều hành Android được lưu trữ an toàn bằng **`EncryptedSharedPreferences`** thông qua thư viện `flutter_secure_storage`.
  Cơ chế này sử dụng hệ thống **Android Keystore** để mã hóa phần cứng dữ liệu trước khi ghi xuống bộ nhớ flash của điện thoại, ngăn chặn việc thiết bị bị root hoặc các ứng dụng độc hại khác truy cập trái phép vào tệp tin cấu hình XML để đánh cắp token đăng nhập.

---

## 4. CÁC CÂU HỎI VỀ KIẾN TRÚC ĐỒNG BỘ NGOẠI TUYẾN (OFFLINE-FIRST SYNC)

### HĐ Hỏi: Tại sao em không dùng SharedPreferences để lưu lịch sử tập luyện ngoại tuyến? Em đã thiết kế hệ thống đồng bộ offline như thế nào?
* **Trả lời:** 
  * **Hạn chế của SharedPreferences:** SharedPreferences chỉ phù hợp lưu trữ các cấu hình nhỏ Key-Value đơn giản (như cài đặt ứng dụng, cờ điểm danh hôm nay). Đối với dữ liệu lịch sử tập luyện có tính giao dịch cao và cấu trúc phức tạp, việc ghi đè liên tục các chuỗi JSON lớn vào SharedPreferences rất dễ gây lỗi hỏng tệp tin cấu hình XML hoặc mất mát dữ liệu.
  * **Giải pháp:** Ứng dụng của em sử dụng cơ sở dữ liệu cục bộ có cấu trúc **SQLite (thông qua Hive/sqflite)** để lưu trữ lịch sử tập luyện offline dưới dạng giao dịch an toàn (transactional safety).
  * **Cơ chế đồng bộ:**
    1. Khi kết thúc tập luyện trong trạng thái mất mạng (Offline), bản ghi sẽ được lưu vào hàng đợi đồng bộ của SQLite cục bộ và đánh dấu cờ `is_synced = false`.
    2. Ứng dụng tích hợp bộ lắng nghe trạng thái mạng (`Connectivity Listener`). Khi phát hiện thiết bị kết nối mạng trực tuyến trở lại, một tiến trình ngầm sẽ tự động kích hoạt để đẩy các bản ghi chưa đồng bộ lên Supabase.

### HĐ Hỏi: Làm thế nào em tránh được việc đồng bộ trùng lặp dữ liệu (double sync) khi người dùng mất kết nối mạng và gửi lại (retry) nhiều lần?
* **Trả lời:** 
  Em giải quyết bằng cơ chế **Idempotency** (Tính độc lập với số lần gọi) kết hợp ràng buộc duy nhất:
  1. **Sinh UUID ở Client:** Mỗi bản ghi lịch sử tập ngoại tuyến khi khởi tạo sẽ được sinh sẵn một khóa định danh toàn cầu duy nhất UUID v4 ngay tại thiết bị khách (`client_uuid`).
  2. **Ràng buộc duy nhất trên Server:** Bảng `workout_history` trên cơ sở dữ liệu Supabase được thiết lập khóa ràng buộc duy nhất (`UNIQUE Constraint`) trên cột `client_uuid`.
  3. **Lệnh UPSERT:** Tiến trình đồng bộ sử dụng lệnh `UPSERT` (`INSERT ... ON CONFLICT (client_uuid) DO NOTHING`). Nếu gói tin bị gửi trùng lặp nhiều lần do retry, cơ sở dữ liệu sẽ tự động bỏ qua (DO NOTHING) các yêu cầu sau vì trùng `client_uuid`, tránh nhân đôi dữ liệu.

### HĐ Hỏi: Điều gì xảy ra nếu token hết hạn giữa chừng khi ứng dụng đang chạy tiến trình đồng bộ ngầm?
* **Trả lời:** 
  Nếu token xác thực hết hạn giữa chừng, Supabase API sẽ trả về mã lỗi 401 Unauthorized. 
  Hệ thống của em sẽ bắt lỗi này, tạm thời ngưng hàng đợi đồng bộ, và tự động thực hiện luồng **Refresh Token** ngầm bằng cách gửi mã `refresh_token` (được lưu an toàn trong Secure Storage) lên Supabase Auth để lấy một `access_token` mới. Sau khi có token mới hợp lệ, tiến trình sẽ tự động tiếp tục đồng bộ các bản ghi còn lại mà không làm gián đoạn trải nghiệm của người dùng.

### HĐ Hỏi: Nếu người dùng đăng nhập tài khoản trên nhiều thiết bị và cùng sửa dữ liệu ngoại tuyến thì xử lý xung đột thế nào?
* **Trả lời:** 
  Ứng dụng áp dụng nguyên tắc giải quyết xung đột **Server-side Last-Write-Wins** (Máy chủ ghi nhận cuối cùng sẽ thắng):
  * Dữ liệu trên server và local đều chứa trường mốc thời gian cập nhật `updated_at`.
  * Khi tiến trình đồng bộ phát hiện xung đột phiên bản, hệ thống sẽ ưu tiên bản ghi có mốc thời gian cập nhật mới nhất do server chứng thực để ghi đè đồng nhất trạng thái cho tất cả các thiết bị.

### HĐ Hỏi: Làm sao em đảm bảo tính toàn vẹn của chuỗi ngày tập liên tục (Streak) mà không bị người dùng điều chỉnh ngày giờ hệ thống trên điện thoại để gian lận?
* **Trả lời:** 
  * **Không dựa vào thời gian của điện thoại khách:** Thuật toán tính toán và duy trì chuỗi Streak điểm danh hoàn toàn được xử lý ở phía máy chủ (**Server-side**).
  * Khi người dùng điểm danh, hệ thống gọi một hàm PostgreSQL Function trên Supabase. Hàm này sẽ lấy thời gian chuẩn UTC của máy chủ (`timezone('utc'::text, now())`) để so sánh khoảng cách ngày giữa lượt điểm danh mới và lượt cũ.
  * Nếu khoảng cách đúng bằng 1 ngày chuẩn, Streak được cộng 1; nếu lớn hơn 1 ngày, Streak tự động reset về 1. Dữ liệu local chỉ đóng vai trò hiển thị tạm thời (Offline cache) và sẽ luôn được ghi đè chuẩn xác theo dữ liệu đồng bộ về từ Server.

---

## 5. CÁC CÂU HỎI VỀ QUYỀN RIÊNG TƯ & CAMERA STREAM

### HĐ Hỏi: Ứng dụng bắt buộc phải mở camera để theo dõi người tập, em bảo mật hình ảnh cá nhân và quyền riêng tư của họ như thế nào?
* **Trả lời:** 
  Đây là ưu tiên bảo mật hàng đầu của đề tài. Ứng dụng tích hợp **Chính sách quyền riêng tư nghiêm ngặt**:
  1. **Xử lý hoàn toàn trên thiết bị (On-device Processing):** Luồng hình ảnh camera được truyền trực tiếp vào bộ nhớ RAM tạm thời của điện thoại. Mô hình học máy chạy cục bộ trên chip xử lý của thiết bị thông qua Google ML Kit SDK để trích xuất tọa độ 33 điểm khớp xương.
  2. **Hủy ảnh tức thời:** Ngay sau khi trích xuất được tọa độ (mất khoảng vài mili giây), khung hình camera gốc sẽ bị hệ thống **hủy bỏ ngay lập tức** khỏi bộ nhớ RAM.
  3. **Không lưu trữ, không truyền tải:** Ứng dụng cam kết không ghi hình, không chụp ảnh màn hình, không lưu trữ video dưới dạng file vật lý và tuyệt đối không truyền tải bất kỳ dữ liệu hình ảnh nào qua mạng internet lên server. Dữ liệu duy nhất đồng bộ lên Supabase là các con số thống kê buổi tập (số reps, calo, thời gian, số lỗi tư thế).

---

## 6. CÁC CÂU HỎI VỀ KIỂM THỬ & THỰC NGHIỆM (CHƯƠNG 4)

### HĐ Hỏi: Em đã tiến hành thực nghiệm kiểm thử thuật toán nhận diện tư thế dưới những kịch bản ngoại cảnh nào?
* **Trả lời:** 
  Em đã thiết kế kiểm thử ma trận thực nghiệm trên 5 người dùng (chiều cao từ 1.55m đến 1.85m) dưới các điều kiện ngoại cảnh nghiêm ngặt:
  * **Khoảng cách:** Thử nghiệm tại các khoảng cách 1.5m, 2.0m - 3.0m, và 3.5m.
  * **Góc camera:** Thử nghiệm tại các góc xoay $0^\circ$ (chính diện), $30^\circ - 45^\circ$ (nghiêng), và $60^\circ$ (chéo sâu).
  * **Điều kiện ánh sáng:** Thử nghiệm trong phòng đủ sáng (>300 lux), thiếu sáng (<100 lux), và ngược sáng mạnh.
  * **Loại camera:** Kiểm thử so sánh hiệu năng giữa camera trước và camera sau của thiết bị.

### HĐ Hỏi: Kết quả kiểm thử thực nghiệm thu được cụ thể là gì? Đâu là điều kiện hoạt động tối ưu của ứng dụng?
* **Trả lời:** 
  Kết quả thực nghiệm chi tiết (đã trình bày ở Chương 4):
  * **Khoảng cách tối ưu:** Từ **2.0m đến 3.0m** đạt độ chính xác cao nhất (trung bình **98.2%**). Khoảng cách 1.5m quá gần khiến một số khớp chân bị lọt khỏi khung hình (độ chính xác giảm còn 88.5%). Khoảng cách 3.5m quá xa khiến điểm khớp nhỏ bị nhòe (đạt 94.6%).
  * **Góc camera tối ưu:** Từ **$0^\circ$ đến $30^\circ$** đạt độ chính xác từ **96.8% đến 97.5%**. Góc chéo sâu $60^\circ$ giảm độ chính xác xuống còn 91.2% do hiện tượng tự che khuất các khớp ở phía xa camera (self-occlusion).
  * **Ánh sáng tối ưu:** Điều kiện đủ sáng đạt **98.5%**. Điều kiện thiếu sáng đạt **92.4%** (độ trễ xử lý tăng khoảng 15ms do cảm biến máy ảnh phải tăng phơi sáng). Điều kiện ngược sáng đạt **89.0%** (do bóng người tập bị tối đen, nhờ có bộ lọc nội suy và visibility score nên hệ thống vẫn duy trì hoạt động tốt thay vì bị sập hoàn toàn).
  * **Độ trễ xử lý (Latency):** Camera sau đạt độ trễ trung bình **110ms**, camera trước đạt **125ms** (độ trễ hoàn toàn đáp ứng tốt thời gian thực, không gây cảm giác giật lag cho người tập).

---

## 💡 LỜI KHUYÊN KHI TRẢ LỜI VẤN ĐÁP:
1. **Tự tin và bình tĩnh:** Khi Hội đồng hỏi về thuật toán, hãy nhấn mạnh rằng các logic hình học (tính góc vectơ 3D) và máy trạng thái đều do em tự thiết kế dựa trên các khuyến cáo y học thể thao chuẩn của **ACSM [12]** (Trường Y học Thể thao Hoa Kỳ).
2. **Nêu rõ vai trò của các thư viện:** Rõ ràng về việc Google ML Kit cung cấp tọa độ điểm khớp (Landmarks), còn thuật toán chuyển đổi tọa độ thành các reps tập chuẩn xác, vẽ bộ xương màu xanh/đỏ chỉ thị tư thế và phát âm thanh cảnh báo lỗi là do mã nguồn Flutter của em xử lý.
3. **Thừa nhận hạn chế một cách khoa học:** Nếu bị hỏi về trường hợp ánh sáng quá tối hay khoảng cách quá gần gây mất nét, hãy trả lời: *"Đó là giới hạn vật lý của camera điện thoại và mô hình BlazePose gốc. Tuy nhiên, ứng dụng của em đã giảm thiểu lỗi này bằng cách đưa ra cảnh báo hiển thị trên màn hình nhắc nhở người dùng điều chỉnh khoảng cách đứng, kết hợp bộ lọc trung bình động 5 frames để bù đắp sai số."*

Chúc bạn có một buổi bảo vệ luận văn xuất sắc và đạt điểm số tối đa!
