import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class WorkoutDraftService {
  static const String _draftKey = 'today_workout_draft';

  Future<void> saveDraftWorkout({
    required String exerciseType,
    required String exerciseName,
    required int targetCount,
    required bool noSplit,
    int completedCount = 0,
    String? sourceTag,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now();
    final todayKey = _getDateKey(now);

    final draft = {
      'dateKey': todayKey,
      'exerciseType': exerciseType,
      'exerciseName': exerciseName,
      'targetCount': targetCount,
      'noSplit': noSplit,
      'completedCount': completedCount,
      'sourceTag': sourceTag,
      'savedAt': now.toIso8601String(),
    };

    await prefs.setString(_draftKey, jsonEncode(draft));
    debugPrint('ok');
  }

  Future<Map<String, dynamic>?> getTodayDraftWorkout() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_draftKey);
    if (raw == null || raw.isEmpty) return null;

    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final dateKey = decoded['dateKey'] as String?;
      if (dateKey != null && dateKey != _getDateKey(DateTime.now())) {
        await prefs.remove(_draftKey);
        return null;
      }
      return decoded;
    } catch (_) {
      await prefs.remove(_draftKey);
      return null;
    }
  }

  Future<void> clearTodayDraftWorkout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_draftKey);
  }

  String _getDateKey(DateTime date) {
    return '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }
}
