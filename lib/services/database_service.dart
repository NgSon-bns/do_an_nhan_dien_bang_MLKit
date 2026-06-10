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
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) return;

    try {
      await _client.from('workout_history').insert({
        'user_id': user.id,
        'exercise_type': exerciseType,
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
      return {
        'totalCalories': 0.0,
        'totalMinutes': 0,
        'workoutsCount': 0,
      };
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
      return {
        'totalCalories': 0.0,
        'totalMinutes': 0,
        'workoutsCount': 0,
      };
    }
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
