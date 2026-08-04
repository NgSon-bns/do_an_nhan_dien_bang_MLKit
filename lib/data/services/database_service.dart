import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class DatabaseService {
  SupabaseClient get _client => Supabase.instance.client;

  /// Lấy toàn bộ danh sách bài tập động từ bảng 'bai_tap' trên Supabase
  Future<List<Map<String, dynamic>>> getExercisesFromDatabase() async {
    try {
      final List<dynamic> data = await _client
          .from('bai_tap')
          .select()
          .order('ma_bai_tap', ascending: true);
      return List<Map<String, dynamic>>.from(data);
    } catch (e) {
      debugPrint('Lỗi lấy danh sách bài tập từ CSDL: $e');
      return [];
    }
  }

  /// Lưu kết quả một buổi tập mới lên Supabase Cloud PostgreSQL (Tiếng Việt)
  Future<void> saveWorkoutResult({
    required String exerciseType,
    required int repsCount,
    required int durationSeconds,
    required double caloriesBurned,
    required int incorrectPostures,
    String? sourceTag,
    List<String>? danhSachAnhSai,
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) return;

    try {
      final exerciseIdValue =
          sourceTag != null && sourceTag.startsWith('recommended:')
          ? '$exerciseType::$repsCount::recommended'
          : '$exerciseType::$repsCount::custom';

      await _client.from('lich_su_tap_luyen').insert({
        'ma_nguoi_dung': user.id,
        'ma_bai_tap_rieng': exerciseIdValue,
        'so_lan_tap': repsCount,
        'thoi_gian_tap': durationSeconds,
        'calo_tieu_hao': caloriesBurned,
        'so_lan_sai_tu_the': incorrectPostures,
        'danh_sach_anh_sai': danhSachAnhSai,
      });
    } catch (e) {
      debugPrint('Lỗi đồng bộ lịch sử tập: $e');
    }
  }

  /// Lấy tổng số calo tiêu hao và tổng thời gian tập luyện thực tế của người dùng hiện tại
  Future<Map<String, dynamic>> getWorkoutStats() async {
    final user = _client.auth.currentUser;
    if (user == null) {
      return {'totalCalories': 0.0, 'totalMinutes': 0, 'workoutsCount': 0};
    }

    try {
      final List<dynamic> data = await _client
          .from('lich_su_tap_luyen')
          .select('calories_burned:calo_tieu_hao, duration_seconds:thoi_gian_tap')
          .eq('ma_nguoi_dung', user.id);

      double totalCalories = 0.0;
      int totalSeconds = 0;

      for (var row in data) {
        totalCalories += (row['calories_burned'] as num?)?.toDouble() ?? 0.0;
        totalSeconds += (row['duration_seconds'] as num?)?.toInt() ?? 0;
      }

      int totalMinutes = (totalSeconds / 60).round();

      return {
        'totalCalories': totalCalories,
        'totalMinutes': totalMinutes,
        'workoutsCount': data.length,
      };
    } catch (e) {
      debugPrint('Lỗi truy vấn thống kê: $e');
      return {'totalCalories': 0.0, 'totalMinutes': 0, 'workoutsCount': 0};
    }
  }

  Future<List<Map<String, dynamic>>> getCompletedExerciseRecordsForDate(
    DateTime day,
  ) async {
    final user = _client.auth.currentUser;
    if (user == null) return [];

    try {
      final startQuery = DateTime.utc(day.year, day.month, day.day).subtract(const Duration(days: 1));
      final endQuery = DateTime.utc(day.year, day.month, day.day).add(const Duration(days: 2));

      final List<dynamic> data = await _client
          .from('lich_su_tap_luyen')
          .select('ma_bai_tap_rieng, so_lan_tap, ngay_tao')
          .eq('ma_nguoi_dung', user.id)
          .gte('ngay_tao', startQuery.toIso8601String())
          .lt('ngay_tao', endQuery.toIso8601String());

      final String targetDateStr = '${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';
      final List<Map<String, dynamic>> filteredList = [];

      for (var row in data) {
        final String? createdAtStr = row['ngay_tao'] as String?;
        if (createdAtStr != null) {
          final DateTime localDateTime = DateTime.parse(createdAtStr).toLocal();
          final String localDateStr = '${localDateTime.year}-${localDateTime.month.toString().padLeft(2, '0')}-${localDateTime.day.toString().padLeft(2, '0')}';
          
          if (localDateStr == targetDateStr) {
            filteredList.add({
              'exercise_id': (row['ma_bai_tap_rieng'] as String?) ?? '',
              'reps_count': (row['so_lan_tap'] as num?)?.toInt() ?? 0,
            });
          }
        }
      }

      return filteredList;
    } catch (e) {
      debugPrint('Lỗi truy vấn lịch sử theo ngày: $e');
      return [];
    }
  }

  Future<List<String>> getCompletedExerciseTypesForDate(DateTime day) async {
    final records = await getCompletedExerciseRecordsForDate(day);
    return records
        .map<String>((row) => (row['exercise_id'] as String?) ?? '')
        .where((exerciseId) => exerciseId.isNotEmpty)
        .toList();
  }

  /// Lấy danh sách lịch sử tập luyện gần đây
  Future<List<Map<String, dynamic>>> getRecentWorkouts({int limit = 10}) async {
    final user = _client.auth.currentUser;
    if (user == null) return [];

    try {
      final List<dynamic> data = await _client
          .from('lich_su_tap_luyen')
          .select('exercise_id:ma_bai_tap_rieng, reps_count:so_lan_tap, duration_seconds:thoi_gian_tap, calories_burned:calo_tieu_hao, incorrect_postures:so_lan_sai_tu_the, created_at:ngay_tao, danh_sach_anh_sai')
          .eq('ma_nguoi_dung', user.id)
          .order('ngay_tao', ascending: false)
          .limit(limit);

      return List<Map<String, dynamic>>.from(data);
    } catch (e) {
      return [];
    }
  }
}
