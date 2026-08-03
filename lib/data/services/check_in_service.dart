import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'database_service.dart';

class CheckInService {
  final DatabaseService _databaseService = DatabaseService();

  String _getUserId() {
    final user = Supabase.instance.client.auth.currentUser;
    return user?.id ?? 'guest';
  }

  String _datesKey(String userId) => 'check_in_dates_$userId';
  String _streakKey(String userId) => 'check_in_streak_$userId';
  String _lastKey(String userId) => 'last_check_in_date_$userId';

  // Tính toán chuỗi ngày liên tục (streak) chuẩn xác theo nguyên tắc:
  // - Chỉ tính nếu có điểm danh hôm nay hoặc ngày hôm qua
  // - Lùi từng ngày liên tiếp về quá khứ để đếm chuỗi
  int _calculateStreak(List<String> sortedDates) {
    if (sortedDates.isEmpty) return 0;

    final today = _getTodayDateString();
    final yesterday = _getDateString(DateTime.now().subtract(const Duration(days: 1)));

    final reversedDates = List<String>.from(sortedDates)..sort((a, b) => b.compareTo(a));
    final lastDate = reversedDates.first;

    // Nếu ngày điểm danh gần nhất không phải hôm nay hoặc hôm qua => Chuỗi bị đứt (= 0)
    if (lastDate != today && lastDate != yesterday) {
      return 0;
    }

    int streak = 1;
    DateTime checkDate = DateTime.parse(lastDate);
    while (true) {
      checkDate = checkDate.subtract(const Duration(days: 1));
      final checkDateStr = _getDateString(checkDate);
      if (reversedDates.contains(checkDateStr)) {
        streak++;
      } else {
        break;
      }
    }
    return streak;
  }

  // Đồng bộ lịch sử điểm danh từ Supabase CSDL xuống SharedPreferences cục bộ đúng theo user_id
  Future<void> syncCheckInHistoryFromSupabase() async {
    try {
      final client = Supabase.instance.client;
      final user = client.auth.currentUser;
      if (user == null) return;

      final userId = user.id;
      final prefs = await SharedPreferences.getInstance();

      // Dọn dẹp key cũ không theo user_id để tránh dính dữ liệu giữa các tài khoản
      await prefs.remove('check_in_dates');
      await prefs.remove('check_in_streak');
      await prefs.remove('last_check_in_date');

      List<String> datesFromDb = [];

      try {
        final List<dynamic> data = await client
            .from('diem_danh')
            .select('ngay_diem_danh')
            .eq('ma_nguoi_dung', userId);

        for (var row in data) {
          final String? dateStr = row['ngay_diem_danh'] as String?;
          if (dateStr != null && !datesFromDb.contains(dateStr)) {
            datesFromDb.add(dateStr);
          }
        }
      } catch (dbError) {
        debugPrint('Bảng diem_danh chưa sẵn sàng, thử tải từ lich_su_tap_luyen: $dbError');
        try {
          final List<dynamic> data = await client
              .from('lich_su_tap_luyen')
              .select('ngay_tao')
              .eq('ma_nguoi_dung', userId)
              .like('ma_bai_tap_rieng', 'check_in%');

          for (var row in data) {
            final String? createdAt = row['ngay_tao'] as String?;
            if (createdAt != null) {
              final dateStr = createdAt.substring(0, 10); // yyyy-MM-dd
              if (!datesFromDb.contains(dateStr)) {
                datesFromDb.add(dateStr);
              }
            }
          }
        } catch (fallbackError) {
          debugPrint('Lỗi fallback khi tải điểm danh: $fallbackError');
        }
      }

      datesFromDb.sort();

      final int streak = _calculateStreak(datesFromDb);
      final String? lastCheckInDate = datesFromDb.isNotEmpty
          ? (List<String>.from(datesFromDb)..sort((a, b) => b.compareTo(a))).first
          : null;

      // Lưu đúng dữ liệu của duy nhất user này
      await prefs.setStringList(_datesKey(userId), datesFromDb);
      await prefs.setInt(_streakKey(userId), streak);
      if (lastCheckInDate != null) {
        await prefs.setString(_lastKey(userId), lastCheckInDate);
      } else {
        await prefs.remove(_lastKey(userId));
      }
    } catch (e) {
      debugPrint('Lỗi đồng bộ lịch sử điểm danh từ Supabase: $e');
    }
  }

  // Tải danh sách ngày đã điểm danh của user hiện tại
  Future<List<String>> getCheckInDates() async {
    final userId = _getUserId();
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_datesKey(userId)) ?? [];
  }

  // Tải chuỗi ngày liên tục (streak) của user hiện tại
  Future<int> getStreak() async {
    final userId = _getUserId();
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_streakKey(userId)) ?? 0;
  }

  // Kiểm tra xem user hiện tại đã điểm danh hôm nay chưa
  Future<bool> hasCheckedInToday() async {
    final userId = _getUserId();
    final prefs = await SharedPreferences.getInstance();
    final today = _getTodayDateString();
    final lastCheckIn = prefs.getString(_lastKey(userId));
    return lastCheckIn == today;
  }

  // Thực hiện điểm danh đúng ngày HÔM NAY cho user hiện tại (chỉ 1 lần/ngày)
  Future<Map<String, dynamic>> performCheckIn() async {
    final userId = _getUserId();
    final prefs = await SharedPreferences.getInstance();
    final today = _getTodayDateString();

    final dates = prefs.getStringList(_datesKey(userId)) ?? [];
    final lastCheckIn = prefs.getString(_lastKey(userId));

    // Nếu hôm nay đã điểm danh rồi -> chặn lại
    if (lastCheckIn == today || dates.contains(today)) {
      final currentStreak = prefs.getInt(_streakKey(userId)) ?? 0;
      return {
        'success': false,
        'streak': currentStreak,
        'message': 'Hôm nay bạn đã điểm danh rồi!',
      };
    }

    // Thêm ngày hôm nay vào danh sách điểm danh
    dates.add(today);
    dates.sort();

    // Tính lại streak chuẩn xác
    final newStreak = _calculateStreak(dates);

    // Cập nhật bộ nhớ máy theo user_id
    await prefs.setStringList(_datesKey(userId), dates);
    await prefs.setString(_lastKey(userId), today);
    await prefs.setInt(_streakKey(userId), newStreak);

    // Đồng bộ lên CSDL Supabase (Tiếng Việt)
    try {
      final client = Supabase.instance.client;
      final user = client.auth.currentUser;
      if (user != null) {
        try {
          await client.from('diem_danh').insert({
            'ma_nguoi_dung': user.id,
            'ngay_diem_danh': today,
          });
          debugPrint('Đã lưu thành công điểm danh vào bảng diem_danh cho user: ${user.id}');
        } catch (checkInErr) {
          debugPrint('Lỗi insert bảng diem_danh: $checkInErr');
          await _databaseService.saveWorkoutResult(
            exerciseType: 'check_in',
            repsCount: 1,
            durationSeconds: 0,
            caloriesBurned: 0.0,
            incorrectPostures: 0,
          );
        }
      }
    } catch (e) {
      debugPrint('Lỗi đồng bộ điểm danh lên database: $e');
    }

    return {
      'success': true,
      'streak': newStreak,
      'message': 'Điểm danh thành công!',
    };
  }

  // Lấy chuỗi ngày thứ Hai -> Chủ Nhật của tuần hiện tại và trạng thái điểm danh tương ứng của user hiện tại
  Future<List<Map<String, dynamic>>> getCurrentWeekCheckInStatus() async {
    final dates = await getCheckInDates();
    final now = DateTime.now();

    // Tìm ngày thứ Hai của tuần này
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

  String _getTodayDateString() {
    return _getDateString(DateTime.now());
  }

  String _getDateString(DateTime date) {
    return date.toIso8601String().substring(0, 10);
  }
}
