# TÀI LIỆU CÔNG THỨC KHOA HỌC THỂ THAO & THUẬT TOÁN THÍCH ỨNG TRONG HỆ THỐNG AI COACH

Tài liệu này tổng hợp toàn bộ cơ sở lý thuyết, công thức toán học, cơ chế **lựa chọn bài tập thích ứng sinh học (Adaptive Exercise Selection)** và **hệ thống điểm danh tích lũy Streak** của tính năng **AI Coach** để phục vụ viết báo cáo luận văn tốt nghiệp.

---

## 1. Công thức tính Tỷ lệ trao đổi chất cơ bản (BMR - Basal Metabolic Rate)

### Cơ sở lý thuyết:
BMR (Basal Metabolic Rate) là lượng năng lượng tối thiểu (tính bằng calo) mà cơ thể cần để duy trì các chức năng sống cơ bản (hô hấp, tuần hoàn, điều hòa thân nhiệt, sản sinh tế bào) khi ở trạng thái nghỉ ngơi hoàn toàn.

Hệ thống sử dụng **Công thức Mifflin-St Jeor** (được công bố năm 1990), hiện là công thức chuẩn được Hiệp hội Dinh dưỡng Hoa Kỳ (ADA) khuyên dùng nhờ độ chính xác cao đối với thể trạng người hiện đại.

### Công thức toán học:
Để tối ưu hóa cho ứng dụng khi không bắt buộc người dùng chọn giới tính (giảm thiểu bước nhập liệu), hệ thống áp dụng công thức trung bình giới tính như sau:

$$\text{BMR} = 10 \times W + 6.25 \times H - 5 \times A - 78$$

Trong đó:
* $W$ (Weight): Cân nặng của người dùng (tính bằng kg).
* $H$ (Height): Chiều cao của người dùng (tính bằng cm).
* $A$ (Age): Tuổi của người dùng (tính bằng năm).
* Hệ số $-78$ là trung vị giữa hệ số của Nam ($+5$) và Nữ ($-161$).

---

## 2. Công thức tính Tổng tiêu hao năng lượng hàng ngày (TDEE - Total Daily Energy Expenditure)

### Cơ sở lý thuyết:
TDEE (Total Daily Energy Expenditure) là tổng lượng calo cơ thể thực tế tiêu thụ trong 24 giờ, bao gồm cả năng lượng cho hoạt động thể chất và tiêu hóa thức ăn.

### Công thức toán học:
TDEE được tính bằng cách nhân BMR với hệ số hoạt động thể chất (PAL - Physical Activity Level):

$$\text{TDEE} = \text{BMR} \times \text{PAL}$$

Trong hệ thống AI Coach, đối với đa số người dùng phổ thông bắt đầu luyện tập, hệ số hoạt động được mặc định ở mức **Vận động nhẹ (Lightly Active)**:

$$\text{PAL} = 1.375$$

Do đó:
$$\text{TDEE} = \text{BMR} \times 1.375$$

---

## 3. Xác định mục tiêu Calo cần tiêu thụ qua buổi tập (Target Workout Calories)

Dựa trên mục tiêu thể hình của người tập, AI Coach tính toán lượng calo cần tiêu thụ trong ngày thông qua các bài tập thể chất ($E_{\text{target}}$):

* **Mục tiêu Giảm cân (Lose Weight)**: Yêu cầu thâm hụt calo bền vững. Năng lượng tiêu hao qua tập luyện được thiết lập chiếm **10% TDEE**.
  $$E_{\text{target}} = \text{TDEE} \times 0.10$$
* **Mục tiêu Tăng cơ (Build Muscle)**: Tập trung vào kích thích cơ lực, năng lượng tiêu hao qua tập luyện chiếm **8% TDEE**.
  $$E_{\text{target}} = \text{TDEE} \times 0.08$$
* **Mục tiêu Giữ dáng (Maintain Shape)**: Tập luyện duy trì sức khỏe, năng lượng tiêu hao qua tập luyện chiếm **6% TDEE**.
  $$E_{\text{target}} = \text{TDEE} \times 0.06$$

*Lưu ý: Để đảm bảo an toàn tập luyện, $E_{\text{target}}$ được giới hạn trong ngưỡng tối thiểu $80\text{ kcal/ngày}$ và tối đa $350\text{ kcal/ngày}$.*

---

## 4. Công thức quy đổi Calo sang số Rep tập luyện và số Giây giữ Plank

Tổng calo mục tiêu của ngày ($E_{\text{target}}$) được chia đều cho 4 bài tập trong thực đơn đề xuất. Lượng calo phân bổ cho mỗi bài tập là:

$$E_{\text{exercise}} = \frac{E_{\text{target}}}{4}$$

Dựa trên chỉ số calo tiêu hao mỗi phút ($\text{CPM} - \text{Calories Per Minute}$) của từng bài tập cụ thể, hệ thống quy đổi ra mục tiêu vận động:

### A. Đối với bài tập tính số lần (Rep-based Exercises)
Giả định tốc độ thực hiện động tác chuẩn y khoa trung bình là **3 giây/rep** (tương đương $0.05$ phút/rep).
Lượng calo tiêu hao trên một rep tập là:

$$\text{Calo per Rep} = \text{CPM} \times 0.05$$

Do đó, số lượng Rep cần thực hiện để đạt mục tiêu calo phân bổ là:

$$\text{Reps} = \frac{E_{\text{exercise}}}{\text{CPM} \times 0.05} = \frac{E_{\text{target}}}{0.2 \times \text{CPM}}$$

*Số Reps sau khi tính sẽ được làm tròn đến bội số của 5 gần nhất và khống chế trong giới hạn an toàn vật lý của khớp.*

### B. Đối với bài tập tính thời gian giữ (Duration-based Exercises)
Năng lượng tiêu hao trên mỗi giây giữ Plank là:

$$\text{Calo per Second} = \frac{\text{CPM}}{60}$$

Do đó, số giây giữ Plank tối thiểu cần thực hiện là:

$$\text{Seconds} = \frac{E_{\text{exercise}}}{\text{Calo per Second}} = \frac{E_{\text{target}} \times 15}{\text{CPM}}$$

*Số giây sau khi tính sẽ được làm tròn đến bội số của 10 giây gần nhất.*

---

## 5. Thuật toán Lựa chọn bài tập Thích ứng Sinh học (Adaptive Exercise Selection)

Để tránh trường hợp đề xuất rập khuôn cho mọi đối tượng, hệ thống tích hợp bộ luật chuyên gia (AI Rule-Engine) tự động lọc và thay đổi danh sách bài tập dựa trên chỉ số **BMI** và **Tuổi** của người dùng:

### A. Quy tắc loại trừ chấn thương khớp (Joint Protection Rule):
* **Đối tượng**: Người thừa cân/béo phì ($\text{BMI} \ge 25.0$) hoặc Người lớn tuổi ($\text{Tuổi} \ge 45$).
* **Hành vi**: Loại bỏ hoàn toàn bài tập **Burpee** (do có lực bật nhảy tác động mạnh có nguy cơ gây chấn thương khớp gối và cột sống lưng dưới sức nặng cơ thể hoặc thoái hóa khớp trung niên). 
* **Giải pháp thay thế**: Chuyển sang bài tập **Push-Up** hoặc **Jumping Jack** ở cường độ được tính toán giảm tải lực phản hồi chân.

### B. Quy tắc tiết kiệm năng lượng cho người gầy (Energy Conservation Rule):
* **Đối tượng**: Người thiếu cân ($\text{BMI} < 18.5$).
* **Hành vi**: Loại bỏ hoàn toàn các bài tập Cardio tiêu tốn quá nhiều calo và nhịp tim nhanh (như **Jumping Jack**, **Burpee**).
* **Giải pháp thay thế**: Tập trung 100% vào các bài tập kháng lực phát triển cơ lực chậm (Strength: **Push-Up**, **Squat**, **Walking Lunge**) để thúc đẩy xây dựng các sợi cơ nạc (muscle hypertrophy) giúp tăng cân an toàn.

### C. Quy tắc rèn luyện thăng bằng cho người trung niên (Balance & Core Rule):
* **Đối tượng**: Người lớn tuổi ($\text{Tuổi} \ge 45$).
* **Hành vi**: Ưu tiên cao bài tập **Plank** (core bụng lưng an toàn không rung xóc) và **Walking Lunge** (bước đi thăng bằng chậm để tăng sự nhạy bén thần kinh vận động hông dưới).

---

## 6. Hệ thống Điểm danh Hàng ngày và Tích lũy Chuỗi Streak (Daily Check-In System)

Để đánh giá mức độ tương tác và tính chuyên cần hàng ngày của người dùng, hệ thống tích hợp **Tính năng điểm danh tích lũy Streak**:

### A. Quy tắc tính Streak (Chuỗi chuyên cần):
* Hệ thống lưu trữ ngày điểm danh cuối cùng (`last_check_in_date`) dưới định dạng ISO `yyyy-MM-dd`.
* Khi người dùng điểm danh ngày hôm nay ($T_{\text{today}}$):
  * Nếu chưa từng điểm danh $\rightarrow \text{Streak} = 1$.
  * Nếu khoảng cách giữa hôm nay và ngày điểm danh cuối cùng là đúng **1 ngày** ($T_{\text{today}} - T_{\text{last}} = 1$) $\rightarrow \text{Streak} = \text{Streak} + 1$ (Duy trì và tăng chuỗi).
  * Nếu khoảng cách lớn hơn **1 ngày** ($T_{\text{today}} - T_{\text{last}} > 1$) $\rightarrow \text{Streak} = 1$ (Bị đứt chuỗi chuyên cần, bắt đầu lại chuỗi mới).
* Thông tin được lưu trữ tối ưu cục bộ bằng `SharedPreferences` để phản hồi tức thì và đồng bộ hóa lên Supabase thông qua thực thể ghi log hoạt động chuyên biệt.

### B. Minh họa Giao diện Điểm danh (Weekly Grid View):
Hệ thống tự động tính ngày thứ Hai đầu tuần và render một thanh lịch gồm 7 ngày (Monday - Sunday) trong tuần hiện tại:
* Ngày đã điểm danh: Hiện màu xanh Neon với dấu Tick ($\checkmark$).
* Ngày hôm nay (Chưa điểm danh): Hiện chấm tròn cam nhấp nháy, mở nút bấm **"ĐIỂM DANH HÔM NAY"**.
* Ngày tương lai: Hiện viền đứt nét màu xám.

---

## 7. Mã nguồn Dart của Hệ thống Điểm danh (Dành cho báo cáo)

### File: `check_in_service.dart`
```dart
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'database_service.dart';

class CheckInService {
  static const String _datesKey = 'check_in_dates';
  static const String _streakKey = 'check_in_streak';
  static const String _lastKey = 'last_check_in_date';

  final DatabaseService _databaseService = DatabaseService();

  Future<List<String>> getCheckInDates() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_datesKey) ?? [];
  }

  Future<int> getStreak() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_streakKey) ?? 0;
  }

  Future<bool> hasCheckedInToday() async {
    final prefs = await SharedPreferences.getInstance();
    final today = _getTodayDateString();
    return prefs.getString(_lastKey) == today;
  }

  Future<Map<String, dynamic>> performCheckIn() async {
    final prefs = await SharedPreferences.getInstance();
    final today = _getTodayDateString();
    final dates = prefs.getStringList(_datesKey) ?? [];
    final lastCheckIn = prefs.getString(_lastKey);
    int streak = prefs.getInt(_streakKey) ?? 0;

    if (lastCheckIn == today) {
      return {'success': false, 'streak': streak, 'message': 'Đã điểm danh hôm nay!'};
    }

    if (lastCheckIn != null) {
      final lastDate = DateTime.parse(lastCheckIn);
      final todayDate = DateTime.parse(today);
      final difference = todayDate.difference(lastDate).inDays;

      if (difference == 1) {
        streak++;
      } else if (difference > 1) {
        streak = 1;
      }
    } else {
      streak = 1;
    }

    dates.add(today);
    await prefs.setStringList(_datesKey, dates);
    await prefs.setString(_lastKey, today);
    await prefs.setInt(_streakKey, streak);

    // Đồng bộ lên Supabase workout_history
    try {
      final client = Supabase.instance.client;
      if (client.auth.currentUser != null) {
        await _databaseService.saveWorkoutResult(
          exerciseType: 'check_in',
          repsCount: 1,
          durationSeconds: 0,
          caloriesBurned: 0.0,
          incorrectPostures: 0,
        );
      }
    } catch (e) {
      // Bỏ qua lỗi kết nối
    }

    return {'success': true, 'streak': streak, 'message': 'Điểm danh thành công!'};
  }

  Future<List<Map<String, dynamic>>> getCurrentWeekCheckInStatus() async {
    final dates = await getCheckInDates();
    final now = DateTime.now();
    final int currentWeekday = now.weekday; 
    final DateTime monday = now.subtract(Duration(days: currentWeekday - 1));

    final List<Map<String, dynamic>> weekStatus = [];
    final List<String> weekdaysNames = ['T2', 'T3', 'T4', 'T5', 'T6', 'T7', 'CN'];

    for (int i = 0; i < 7; i++) {
      final dayDate = monday.add(Duration(days: i));
      final dateStr = _getDateString(dayDate);
      final isToday = dateStr == _getTodayDateString();
      final hasChecked = dates.contains(dateStr);
      final DateTime justDate = DateTime(dayDate.year, dayDate.month, dayDate.day);
      final DateTime justNow = DateTime(now.year, now.month, now.day);

      weekStatus.add({
        'name': weekdaysNames[i],
        'date': dateStr,
        'isToday': isToday,
        'hasChecked': hasChecked,
        'isFuture': justDate.isAfter(justNow),
      });
    }
    return weekStatus;
  }

  String _getTodayDateString() => _getDateString(DateTime.now());
  String _getDateString(DateTime date) => date.toIso8601String().substring(0, 10);
}
```
