import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class DatabaseService {
  SupabaseClient get _client => Supabase.instance.client;

  /// Lưu kết quả một buổi tập mới lên Supabase Cloud PostgreSQL
  Future<void> saveWorkoutResult({
    required String exerciseType,
    required int repsCount,
    required int durationSeconds,
    required double caloriesBurned,
    required int incorrectPostures,
    String? sourceTag,
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) return;

    try {
      final exerciseIdValue =
          sourceTag != null && sourceTag.startsWith('recommended:')
          ? '$exerciseType::$repsCount::recommended'
          : '$exerciseType::$repsCount::custom';

      await _client.from('workout_history').insert({
        'user_id': user.id,
        'exercise_id': exerciseIdValue,
        'reps_count': repsCount,
        'duration_seconds': durationSeconds,
        'calories_burned': caloriesBurned,
        'incorrect_postures': incorrectPostures,
      });
    } catch (e) {
      // Bỏ qua lỗi hoặc in debug log để tránh crash màn hình
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
          .from('workout_history')
          .select('calories_burned, duration_seconds')
          .eq('user_id', user.id);

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

  /// Lấy danh sách bài tập đã hoàn thành trong một ngày cụ thể dựa trên workout_history
  Future<List<Map<String, dynamic>>> getCompletedExerciseRecordsForDate(
    DateTime day,
  ) async {
    final user = _client.auth.currentUser;
    if (user == null) return [];

    try {
      final startOfDay = DateTime.utc(day.year, day.month, day.day);
      final endOfDay = startOfDay.add(const Duration(days: 1));

      final List<dynamic> data = await _client
          .from('workout_history')
          .select('exercise_id, reps_count')
          .eq('user_id', user.id)
          .gte('created_at', startOfDay.toIso8601String())
          .lt('created_at', endOfDay.toIso8601String());

      return data
          .map<Map<String, dynamic>>(
            (row) => {
              'exercise_id': (row['exercise_id'] as String?) ?? '',
              'reps_count': (row['reps_count'] as num?)?.toInt() ?? 0,
            },
          )
          .toList();
    } catch (e) {
      debugPrint('Lỗi truy vấn workout_history theo ngày: $e');
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
          .from('workout_history')
          .select()
          .eq('user_id', user.id)
          .order('created_at', ascending: false)
          .limit(limit);

      return List<Map<String, dynamic>>.from(data);
    } catch (e) {
      return [];
    }
  }
}
