import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'database_service.dart';

class CheckInService {
  static const String _datesKey = 'check_in_dates';
  static const String _streakKey = 'check_in_streak';
  static const String _lastKey = 'last_check_in_date';

  final DatabaseService _databaseService = DatabaseService();

  // Đồng bộ lịch sử điểm danh từ Supabase CSDL xuống SharedPreferences cục bộ
  Future<void> syncCheckInHistoryFromSupabase() async {
    try {
      final client = Supabase.instance.client;
      final user = client.auth.currentUser;
      if (user == null) return;

      List<String> datesFromDb = [];

      try {
        final List<dynamic> data = await client
            .from('check_ins')
            .select('check_in_date')
            .eq('user_id', user.id);

        for (var row in data) {
          final String? dateStr = row['check_in_date'] as String?;
          if (dateStr != null && !datesFromDb.contains(dateStr)) {
            datesFromDb.add(dateStr);
          }
        }
      } catch (dbError) {
        debugPrint('Bảng check_ins chưa sẵn sàng, thử tải từ workout_history: $dbError');
        try {
          final List<dynamic> data = await client
              .from('workout_history')
              .select('created_at')
              .eq('user_id', user.id)
              .like('exercise_id', 'check_in%');

          for (var row in data) {
            final String? createdAt = row['created_at'] as String?;
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

      if (datesFromDb.isEmpty) return;

      final prefs = await SharedPreferences.getInstance();
      final List<String> dates = prefs.getStringList(_datesKey) ?? [];

      bool hasNewData = false;
      for (var dbDate in datesFromDb) {
        if (!dates.contains(dbDate)) {
          dates.add(dbDate);
          hasNewData = true;
        }
      }

      if (!hasNewData) return;

      dates.sort();

      int streak = 0;
      String? lastCheckInDate;
      if (dates.isNotEmpty) {
        final reversedDates = List<String>.from(dates)..sort((a, b) => b.compareTo(a));
        lastCheckInDate = reversedDates.first;

        final today = _getTodayDateString();
        final yesterday = _getDateString(DateTime.now().subtract(const Duration(days: 1)));

        if (lastCheckInDate == today || lastCheckInDate == yesterday) {
          streak = 1;
          DateTime checkDate = DateTime.parse(lastCheckInDate);
          while (true) {
            checkDate = checkDate.subtract(const Duration(days: 1));
            final checkDateStr = _getDateString(checkDate);
            if (dates.contains(checkDateStr)) {
              streak++;
            } else {
              break;
            }
          }
        } else {
          streak = 0;
        }
      }

      await prefs.setStringList(_datesKey, dates);
      await prefs.setInt(_streakKey, streak);
      if (lastCheckInDate != null) {
        await prefs.setString(_lastKey, lastCheckInDate);
      }
    } catch (e) {
      debugPrint('Lỗi đồng bộ lịch sử điểm danh từ Supabase: $e');
    }
  }

  // Tải danh sách ngày đã điểm danh
  Future<List<String>> getCheckInDates() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_datesKey) ?? [];
  }

  // Tải chuỗi ngày liên tục (streak)
  Future<int> getStreak() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_streakKey) ?? 0;
  }

  // Kiểm tra xem đã điểm danh hôm nay chưa
  Future<bool> hasCheckedInToday() async {
    final prefs = await SharedPreferences.getInstance();
    final today = _getTodayDateString();
    final lastCheckIn = prefs.getString(_lastKey);
    return lastCheckIn == today;
  }

  // Thực hiện điểm danh
  Future<Map<String, dynamic>> performCheckIn() async {
    final prefs = await SharedPreferences.getInstance();
    final today = _getTodayDateString();
    
    final dates = prefs.getStringList(_datesKey) ?? [];
    final lastCheckIn = prefs.getString(_lastKey);
    int streak = prefs.getInt(_streakKey) ?? 0;

    if (lastCheckIn == today) {
      return {
        'success': false,
        'streak': streak,
        'message': 'Hôm nay bạn đã điểm danh rồi!',
      };
    }

    // Tính toán streak
    if (lastCheckIn != null) {
      try {
        final lastDate = DateTime.parse(lastCheckIn);
        final todayDate = DateTime.parse(today);
        final difference = todayDate.difference(lastDate).inDays;

        if (difference == 1) {
          streak++; // Tiếp tục chuỗi
        } else if (difference > 1) {
          streak = 1; // Đứt chuỗi, bắt đầu lại
        }
      } catch (e) {
        streak = 1;
      }
    } else {
      streak = 1; // Lần đầu tiên
    }

    // Cập nhật local
    dates.add(today);
    await prefs.setStringList(_datesKey, dates);
    await prefs.setString(_lastKey, today);
    await prefs.setInt(_streakKey, streak);

    // Đồng bộ lên Supabase dưới dạng hoạt động đặc biệt 'check_in'
    try {
      final client = Supabase.instance.client;
      final user = client.auth.currentUser;
      if (user != null) {
        try {
          await client.from('check_ins').insert({
            'user_id': user.id,
            'check_in_date': today,
          });
        } catch (_) {
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
      'streak': streak,
      'message': 'Điểm danh thành công!',
    };
  }

  // Lấy chuỗi ngày thứ Hai -> Chủ Nhật của tuần hiện tại và trạng thái điểm danh tương ứng
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

      // Cắt bớt phần sau của ngày để so sánh chuẩn xác
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
