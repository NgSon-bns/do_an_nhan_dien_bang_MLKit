import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

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

  Future<List<Map<String, dynamic>>> _getLocalWorkouts(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getString('cached_completed_workouts_$userId');
    if (data != null && data.isNotEmpty) {
      try {
        final decoded = jsonDecode(data) as List;
        return decoded.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      } catch (e) {
        debugPrint('Lỗi đọc lịch sử tập local: $e');
      }
    }
    return [];
  }

  Future<void> _saveLocalWorkouts(String userId, List<Map<String, dynamic>> list) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('cached_completed_workouts_$userId', jsonEncode(list));
  }

  Future<bool> syncPendingWorkouts() async {
    final user = _client.auth.currentUser;
    if (user == null) {
      debugPrint('[syncPendingWorkouts] User is null. Hủy đồng bộ.');
      return false;
    }

    final localList = await _getLocalWorkouts(user.id);
    final pendingList = localList.where((item) => item['is_synced'] == false).toList();
    if (pendingList.isEmpty) {
      debugPrint('[syncPendingWorkouts] Không có bài tập nào đang chờ đồng bộ.');
      return false;
    }

    debugPrint('[syncPendingWorkouts] Phát hiện ${pendingList.length} bài tập đang chờ đồng bộ. Bắt đầu đẩy lên Cloud...');
    bool anySuccess = false;

    for (var i = 0; i < localList.length; i++) {
      final item = localList[i];
      if (item['is_synced'] == false) {
        try {
          final String? rawExerciseId = item['ma_bai_tap_rieng'];
          final int rawReps = (item['so_lan_tap'] as num?)?.toInt() ?? 0;
          final int rawDuration = (item['thoi_gian_tap'] as num?)?.toInt() ?? 0;
          final double rawCalories = (item['calo_tieu_hao'] as num?)?.toDouble() ?? 0.0;
          final int rawIncorrect = (item['so_lan_sai_tu_the'] as num?)?.toInt() ?? 0;
          final String? rawSource = item['loai_bai_tap'];
          final String? rawDate = item['ngay_tao'];
          
          List<String>? rawImages;
          if (item['danh_sach_anh_sai'] != null) {
            rawImages = List<String>.from(item['danh_sach_anh_sai'] as List);
          }

          debugPrint('[syncPendingWorkouts] Đang đẩy bài tập $rawExerciseId, reps $rawReps, date $rawDate');

          await _client.from('lich_su_tap_luyen').insert({
            'ma_nguoi_dung': user.id,
            'ma_bai_tap_rieng': rawExerciseId,
            'so_lan_tap': rawReps,
            'thoi_gian_tap': rawDuration,
            'calo_tieu_hao': rawCalories,
            'so_lan_sai_tu_the': rawIncorrect,
            'danh_sach_anh_sai': rawImages,
            'loai_bai_tap': rawSource,
            'ngay_tao': rawDate,
          });

          localList[i]['is_synced'] = true;
          anySuccess = true;
          debugPrint('[syncPendingWorkouts] Đẩy bài tập $rawExerciseId thành công!');
        } catch (e) {
          debugPrint('[syncPendingWorkouts] Lỗi đẩy bài tập offline (sẽ tiếp tục thử lại): $e');
        }
      }
    }

    if (anySuccess) {
      await _saveLocalWorkouts(user.id, localList);
      debugPrint('[syncPendingWorkouts] Đã cập nhật trạng thái is_synced = true của các bài tập cục bộ.');
    }
    return anySuccess;
  }

  /// Lưu kết quả một buổi tập mới lên Supabase Cloud PostgreSQL (Offline-first)
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

    final String loaiBaiTap = sourceTag != null && sourceTag.startsWith('recommended:')
        ? 'recommended'
        : 'custom';
    final String nowStr = DateTime.now().toUtc().toIso8601String();

    // 1. Lưu cục bộ trước (Offline-first)
    final localList = await _getLocalWorkouts(user.id);
    final Map<String, dynamic> newRecord = {
      'ma_nguoi_dung': user.id,
      'ma_bai_tap_rieng': exerciseType,
      'so_lan_tap': repsCount,
      'thoi_gian_tap': durationSeconds,
      'calo_tieu_hao': caloriesBurned,
      'so_lan_sai_tu_the': incorrectPostures,
      'danh_sach_anh_sai': danhSachAnhSai,
      'loai_bai_tap': loaiBaiTap,
      'ngay_tao': nowStr,
      'is_synced': false,
    };
    localList.add(newRecord);
    await _saveLocalWorkouts(user.id, localList);

    // 2. Thử đẩy lên database Supabase
    try {
      await _client.from('lich_su_tap_luyen').insert({
        'ma_nguoi_dung': user.id,
        'ma_bai_tap_rieng': exerciseType,
        'so_lan_tap': repsCount,
        'thoi_gian_tap': durationSeconds,
        'calo_tieu_hao': caloriesBurned,
        'so_lan_sai_tu_the': incorrectPostures,
        'danh_sach_anh_sai': danhSachAnhSai,
        'loai_bai_tap': loaiBaiTap,
        'ngay_tao': nowStr,
      });
      // Nếu thành công, cập nhật cờ is_synced thành true
      newRecord['is_synced'] = true;
      await _saveLocalWorkouts(user.id, localList);
    } catch (e) {
      debugPrint('Lỗi đồng bộ lịch sử tập (đã lưu offline): $e');
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
          .select(
            'calories_burned:calo_tieu_hao, duration_seconds:thoi_gian_tap',
          )
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

    final String targetDateStr =
        '${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';

    // 1. Tải từ Cache local trước
    final localList = await _getLocalWorkouts(user.id);
    final List<Map<String, dynamic>> filteredLocal = [];
    for (var row in localList) {
      final String? createdAtStr = row['ngay_tao'] as String?;
      if (createdAtStr != null) {
        final DateTime localDateTime = DateTime.parse(createdAtStr).toLocal();
        final String localDateStr =
            '${localDateTime.year}-${localDateTime.month.toString().padLeft(2, '0')}-${localDateTime.day.toString().padLeft(2, '0')}';

        if (localDateStr == targetDateStr) {
          filteredLocal.add({
            'exercise_id': (row['ma_bai_tap_rieng'] as String?) ?? '',
            'reps_count': (row['so_lan_tap'] as num?)?.toInt() ?? 0,
            'source_tag': (row['loai_bai_tap'] as String?) ?? '',
            'ngay_tao': createdAtStr,
          });
        }
      }
    }

    // 2. Thử truy cập Supabase
    try {
      final startQuery = DateTime.utc(
        day.year,
        day.month,
        day.day,
      ).subtract(const Duration(days: 1));
      final endQuery = DateTime.utc(
        day.year,
        day.month,
        day.day,
      ).add(const Duration(days: 2));

      final List<dynamic> data = await _client
          .from('lich_su_tap_luyen')
          .select('ma_bai_tap_rieng, so_lan_tap, ngay_tao, loai_bai_tap')
          .eq('ma_nguoi_dung', user.id)
          .gte('ngay_tao', startQuery.toIso8601String())
          .lt('ngay_tao', endQuery.toIso8601String());

      final List<Map<String, dynamic>> filteredCloud = [];
      for (var row in data) {
        final String? createdAtStr = row['ngay_tao'] as String?;
        if (createdAtStr != null) {
          final DateTime localDateTime = DateTime.parse(createdAtStr).toLocal();
          final String localDateStr =
              '${localDateTime.year}-${localDateTime.month.toString().padLeft(2, '0')}-${localDateTime.day.toString().padLeft(2, '0')}';

          if (localDateStr == targetDateStr) {
            filteredCloud.add({
              'exercise_id': (row['ma_bai_tap_rieng'] as String?) ?? '',
              'reps_count': (row['so_lan_tap'] as num?)?.toInt() ?? 0,
              'source_tag': (row['loai_bai_tap'] as String?) ?? '',
              'ngay_tao': createdAtStr,
            });
          }
        }
      }

      // Merge Cloud & Local (tránh trùng dựa trên exercise_id và ngay_tao)
      final mergedList = List<Map<String, dynamic>>.from(filteredLocal);
      for (var cloudItem in filteredCloud) {
        final alreadyExists = mergedList.any((localItem) =>
            localItem['exercise_id'] == cloudItem['exercise_id'] &&
            localItem['ngay_tao'] == cloudItem['ngay_tao']);
        if (!alreadyExists) {
          mergedList.add(cloudItem);
        }
      }

      return mergedList;
    } catch (e) {
      debugPrint('Lỗi truy vấn lịch sử theo ngày (Dùng local cache): $e');
      return filteredLocal;
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
          .select(
            'exercise_id:ma_bai_tap_rieng, reps_count:so_lan_tap, duration_seconds:thoi_gian_tap, calories_burned:calo_tieu_hao, incorrect_postures:so_lan_sai_tu_the, created_at:ngay_tao, danh_sach_anh_sai,loai_bai_tap',
          )
          .eq('ma_nguoi_dung', user.id)
          .order('ngay_tao', ascending: false)
          .limit(limit);

      return List<Map<String, dynamic>>.from(data);
    } catch (e) {
      return [];
    }
  }
}
