import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

import 'package:demo/core/theme/app_theme.dart';
import 'package:demo/domain/exercise.dart';
import 'package:demo/data/services/auth_service.dart';
import 'package:demo/data/services/database_service.dart';
import 'package:demo/data/services/workout_draft_service.dart';
import 'workout/workout_screen.dart';
import 'package:demo/presentation/widgets/nutrition_panel.dart';

class RecommendationScreen extends StatefulWidget {
  final List<CameraDescription> cameras;

  const RecommendationScreen({super.key, required this.cameras});

  @override
  State<RecommendationScreen> createState() => _RecommendationScreenState();
}

class _RecommendationScreenState extends State<RecommendationScreen> {
  final AuthService _authService = AuthService();
  SupabaseClient get _client => Supabase.instance.client;
  final WorkoutDraftService _workoutDraftService = WorkoutDraftService();
  Map<String, dynamic>? _todayDraftWorkout;
  double _weight = 0.0;
  double _height = 0.0;
  int _age = 0;
  String _gender = 'male';
  String _userName = '';
  bool _isLoading = true;
  String _selectedGoal = 'maintain';
  int _selectedDayIndex = 7;
  int _selectedWeekIndex = 1;
  final Map<ExerciseType, bool> _noSplitTargets = {};
  final Map<ExerciseType, int> _selectedTargets = {};
  final Map<ExerciseType, bool> _expandedTargetSelectors = {};
  final Map<String, Set<String>> _completedExerciseKeysByDay = {};
  List<Map<String, dynamic>> _todayMealLogs = [];

  // Mảng lưu lịch trình 21 ngày đồng bộ từ Database
  List<Map<String, dynamic>> _savedSchedule = [];

  final Set<ExerciseType> _customSelectedExercises = {};
  bool _isCustomSelectionActive = false;
  final Set<ExerciseType> _tooHeavyExercises = {};
  List<String> _customMuscleGroupLoopHistory = [];

  static const Map<String, List<ExerciseType>> _exerciseGroups = {
    'Thân trên': [ExerciseType.push_up, ExerciseType.plank],
    'Thân dưới': [ExerciseType.squat, ExerciseType.walking_lunge],
    'Toàn thân': [ExerciseType.jumping_jack, ExerciseType.burpee],
  };

  static const Map<String, String> _groupReasons = {
    'Thân trên': 'Push-Up tăng cơ ngực và vai, Plank củng cố core bụng lưng.',
    'Thân dưới':
        'Squat và Walking Lunge phát triển cơ đùi mông và cải thiện cân bằng.',
    'Toàn thân': 'Jumping Jack và Burpee đốt calo toàn thân, tăng nhịp tim.',
  };

  @override
  void initState() {
    super.initState();
    _selectedWeekIndex = 1;
    _selectedDayIndex = 7 + (DateTime.now().weekday - 1);
    _loadInitialData();

    final selectedDate = _getSelectedDayDate(_selectedDayIndex);
    _loadCompletedExercisesForDay(selectedDate);
    _loadMealLogsForDay(selectedDate);
    _refreshTodayDraftWorkout();

    final yesterday = selectedDate.subtract(const Duration(days: 1));
    _loadCompletedExercisesForDay(yesterday);
  }

  Future<void> _loadInitialData() async {
    await _loadPreferencesData();
    await _loadUserProfile(); // Tải profile xong mới có BMI để sinh lịch trình
    await _loadAndSyncSchedule();
  }

  // Chuyển đổi qua lại giữa Enum và String để lưu Database/Prefs
  List<dynamic> _encodeSchedule(List<Map<String, dynamic>> sched) {
    return sched.map((day) {
      final dayCopy = Map<String, dynamic>.from(day);
      if (dayCopy['exercises'] != null) {
        dayCopy['exercises'] = (dayCopy['exercises'] as List).map((ex) {
          final exMap = Map<String, dynamic>.from(ex as Map);
          if (exMap['type'] is ExerciseType) {
            exMap['type'] = (exMap['type'] as ExerciseType).name;
          }
          return exMap;
        }).toList();
      }
      return dayCopy;
    }).toList();
  }

  List<Map<String, dynamic>> _decodeSchedule(List<dynamic> raw) {
    return raw.map((day) {
      final dayCopy = Map<String, dynamic>.from(day as Map);
      if (dayCopy['exercises'] != null) {
        dayCopy['exercises'] = (dayCopy['exercises'] as List).map((ex) {
          final exMap = Map<String, dynamic>.from(ex as Map);
          if (exMap['type'] is String) {
            exMap['type'] =
                _exerciseTypeFromName(exMap['type'] as String) ??
                ExerciseType.jumping_jack;
          }
          return exMap;
        }).toList();
      }
      return dayCopy;
    }).toList();
  }

  // Đồng bộ và Tải lịch trình
  Future<void> _loadAndSyncSchedule() async {
    final prefs = await SharedPreferences.getInstance();
    final user = _client.auth.currentUser;
    final localKey = 'saved_schedule_${user?.id ?? 'guest'}';

    List<Map<String, dynamic>> tempSchedule = [];
    bool hasLocal = false;

    // 1. Đọc từ Local Offline trước
    final localData = prefs.getString(localKey);
    if (localData != null && localData.isNotEmpty) {
      try {
        tempSchedule = _decodeSchedule(jsonDecode(localData));
        hasLocal = true;
      } catch (e) {
        debugPrint('Lỗi đọc lịch trình Local: $e');
      }
    }

    // 2. Fetch từ Supabase (nếu online) và merge
    if (_isSupabaseInitialized && user?.id != 'guest') {
      try {
        final client = Supabase.instance.client;
        final response = await client
            .from('lich_trinh_de_xuat')
            .select('du_lieu_lich_trinh')
            .eq('ma_nguoi_dung', user!.id)
            .maybeSingle();

        if (response != null && response['du_lieu_lich_trinh'] != null) {
          tempSchedule = _decodeSchedule(
            response['du_lieu_lich_trinh'] as List<dynamic>,
          );
          hasLocal = true;
          // Cập nhật lại cache local
          await prefs.setString(
            localKey,
            jsonEncode(_encodeSchedule(tempSchedule)),
          );
        } else if (hasLocal) {
          // Có local nhưng chưa có DB -> đẩy lên DB
          await _syncScheduleToDb(tempSchedule);
        }
      } catch (e) {
        debugPrint('Lỗi tải lịch trình DB (Offline mode): $e');
      }
    }

    // 3. Nếu không có ở đâu cả, tạo mới hoàn toàn
    if (!hasLocal || tempSchedule.isEmpty) {
      double bmi = _height > 0
          ? _weight / ((_height / 100) * (_height / 100))
          : 0.0;
      final rawSchedule = _generateAdaptiveSchedule(_selectedGoal, bmi, _age);
      tempSchedule = _postProcessAdaptiveSchedule(rawSchedule);
      await _saveScheduleLocallyAndDb(tempSchedule);
    }

    if (mounted) {
      setState(() {
        _savedSchedule = tempSchedule;
      });
    }
  }

  // Lưu lịch trình lên Local và DB
  Future<void> _saveScheduleLocallyAndDb(
    List<Map<String, dynamic>> sched,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final userId = _isSupabaseInitialized
        ? Supabase.instance.client.auth.currentUser?.id
        : 'guest';
    final localKey = 'saved_schedule_$userId';

    await prefs.setString(localKey, jsonEncode(_encodeSchedule(sched)));

    if (mounted) {
      setState(() {
        _savedSchedule = sched;
      });
    }

    await _syncScheduleToDb(sched);
  }

  // Đẩy lịch trình lên DB (chạy nền)
  Future<void> _syncScheduleToDb(List<Map<String, dynamic>> sched) async {
    if (!_isSupabaseInitialized) return;
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;

    try {
      await Supabase.instance.client.from('lich_trinh_de_xuat').upsert({
        'ma_nguoi_dung': userId,
        'ngay_cap_nhat': DateTime.now().toIso8601String(),
        'du_lieu_lich_trinh': _encodeSchedule(sched),
      }, onConflict: 'ma_nguoi_dung');
    } catch (e) {
      debugPrint('Mất mạng, chưa đồng bộ lên Database được: $e');
    }
  }

  // Trigger cập nhật lịch trình từ HÔM NAY đổ đi (khi đổi mục tiêu/chỉ số)
  Future<void> _triggerScheduleUpdateFromToday(double currentBmi) async {
    if (_savedSchedule.isEmpty) return;

    final newRaw = _generateAdaptiveSchedule(_selectedGoal, currentBmi, _age);
    final newAdaptive = _postProcessAdaptiveSchedule(newRaw);

    final int todayIndex = DateTime.now().weekday - 1;
    final int safeTodayIndex = 7 + todayIndex;

    // Giữ nguyên từ 0 -> safeTodayIndex - 1. Ghi đè từ safeTodayIndex -> 20.
    List<Map<String, dynamic>> mergedSchedule = List.from(_savedSchedule);
    for (int i = safeTodayIndex; i < mergedSchedule.length; i++) {
      // Đảm bảo bài tập của ngày hôm nay/ngày mai không trùng lặp liên tiếp
      if (i > 0) {
        mergedSchedule[i] = _ensureNoConsecutiveDuplicate(
          newAdaptive[i],
          mergedSchedule[i - 1],
        );
      } else {
        mergedSchedule[i] = newAdaptive[i];
      }
    }

    await _saveScheduleLocallyAndDb(mergedSchedule);
  }

  // Helper đảm bảo ngày hôm sau không trùng bài tập với ngày hôm trước
  Map<String, dynamic> _ensureNoConsecutiveDuplicate(
    Map<String, dynamic> currentDay,
    Map<String, dynamic> previousDay,
  ) {
    if (currentDay['isRest'] == true || previousDay['isRest'] == true) {
      return currentDay;
    }

    final prevExercises =
        (previousDay['exercises'] as List?)
            ?.map((e) => e['type'] as ExerciseType)
            .toSet() ??
        {};

    final currExercises = (currentDay['exercises'] as List?) ?? [];
    List<Map<String, dynamic>> filteredExercises = [];

    for (var ex in currExercises) {
      final ExerciseType type = ex['type'] as ExerciseType;
      // Nếu bài tập trùng với ngày hôm trước, tự động đổi sang bài thay thế an toàn
      if (prevExercises.contains(type)) {
        final alternativeType = _getAlternativeExercise(type);
        filteredExercises.add({
          'type': alternativeType,
          'reason': 'Đổi bài để tránh trùng lặp liên tiếp với ngày hôm trước.',
        });
      } else {
        filteredExercises.add(Map<String, dynamic>.from(ex));
      }
    }

    final updatedDay = Map<String, dynamic>.from(currentDay);
    updatedDay['exercises'] = filteredExercises;
    return updatedDay;
  }

  ExerciseType _getAlternativeExercise(ExerciseType type) {
    switch (type) {
      case ExerciseType.burpee:
        return ExerciseType.jumping_jack;
      case ExerciseType.push_up:
        return ExerciseType.plank;
      case ExerciseType.walking_lunge:
        return ExerciseType.squat;
      case ExerciseType.squat:
        return ExerciseType.walking_lunge;
      case ExerciseType.jumping_jack:
        return ExerciseType.burpee;
      case ExerciseType.plank:
        return ExerciseType.push_up;
    }
  }


  bool _isExerciseBlocked(ExerciseType type, double bmi, int age) {
    if (_tooHeavyExercises.contains(type)) return true;
    if (type == ExerciseType.burpee && (bmi >= 25.0 || age >= 45)) return true;
    return false;
  }

  String _getBlockedReason(ExerciseType type, double bmi, int age) {
    if (_tooHeavyExercises.contains(type)) {
      return '⚠️ Đã bỏ qua bài tập này (quá nặng đối với bạn)';
    }
    if (type == ExerciseType.burpee) {
      if (bmi >= 25.0) {
        return '⚠️ Bị chặn: Thừa cân (BMI ≥ 25), Burpee gây áp lực lớn lên khớp gối';
      }
      if (age >= 45) {
        return '⚠️ Bị chặn: Cao tuổi (≥ 45), Burpee cường độ cao có thể gây ngã nguy hiểm';
      }
    }
    return '';
  }

  bool _isExerciseDoneOnDate(ExerciseType type, DateTime day) {
    final dayKey = _getDayKey(day);
    final completedKeys =
        _completedExerciseKeysByDay[dayKey] ?? const <String>{};
    return completedKeys.any((key) {
      final keyType = _exerciseTypeFromName(key);
      return keyType == type;
    });
  }

  bool _isExerciseSelectableForDay(
    ExerciseType type,
    DateTime selectedDayDate,
    double bmi,
    int age,
  ) {
    final previousDay = selectedDayDate.subtract(const Duration(days: 1));
    return !_isExerciseBlocked(type, bmi, age) &&
        !_isExerciseDoneOnDate(type, previousDay);
  }

  Future<void> _loadPreferencesData() async {
    final prefs = await SharedPreferences.getInstance();
    
    final list = prefs.getStringList('too_heavy_exercises') ?? [];
    setState(() {
      _tooHeavyExercises.clear();
      for (final name in list) {
        final type = _exerciseTypeFromName(name);
        if (type != null) _tooHeavyExercises.add(type);
      }
    });

    final history = prefs.getStringList('custom_muscle_group_loop_history') ?? [];
    setState(() {
      _customMuscleGroupLoopHistory = List<String>.from(history);
    });

    setState(() {
      _isCustomSelectionActive = prefs.getBool('is_custom_selection_active') ?? false;
    });

    final selectedNames = prefs.getStringList('custom_selected_exercises') ?? [];
    setState(() {
      _customSelectedExercises.clear();
      for (final name in selectedNames) {
        final type = _exerciseTypeFromName(name);
        if (type != null) _customSelectedExercises.add(type);
      }
    });
  }

  Future<void> _resetTooHeavyExercises() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('too_heavy_exercises');
    setState(() {
      _tooHeavyExercises.clear();
    });
    
    if (_savedSchedule.isNotEmpty) {
      final int todayIndex = DateTime.now().weekday - 1;
      final int safeTodayIndex = 7 + todayIndex;
      final double bmi = _weight / ((_height / 100) * (_height / 100));
      
      if (_isCustomSelectionActive) {
        final scientificTargets = _calculateScientificReps(
          _weight,
          _height,
          _age,
          _selectedGoal,
          _gender,
          activeCount: _customSelectedExercises.isNotEmpty ? _customSelectedExercises.length : 4,
        );
        final customList = _buildCustomExerciseList(scientificTargets);
        
        List<Map<String, dynamic>> updatedSchedule = List.from(_savedSchedule);
        updatedSchedule[safeTodayIndex]['exercises'] = customList;
        updatedSchedule[safeTodayIndex]['isRest'] = false;
        await _saveScheduleLocallyAndDb(updatedSchedule);
      } else {
        final generated = _generateAdaptiveSchedule(_selectedGoal, bmi, _age);
        List<Map<String, dynamic>> updatedSchedule = List.from(_savedSchedule);
        updatedSchedule[safeTodayIndex]['exercises'] = generated[todayIndex]['exercises'];
        updatedSchedule[safeTodayIndex]['isRest'] = generated[todayIndex]['isRest'];
        await _saveScheduleLocallyAndDb(updatedSchedule);
      }
    }
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Đã khôi phục toàn bộ bài tập bị quá sức!'),
          backgroundColor: AppTheme.neonGreen,
        ),
      );
    }
  }

  void _toggleExerciseGroup(
    String groupName,
    double bmi,
    int age,
    DateTime selectedDayDate,
  ) async {
    if (_hasStartedTodayWorkout()) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Bạn đã bắt đầu tập luyện ngày hôm nay. Không thể thay đổi nhóm cơ!'),
            backgroundColor: AppTheme.errorRed,
          ),
        );
      }
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    final todayStr = selectedDayDate.toIso8601String().split('T')[0];
    final lastSelectionDate = prefs.getString('last_muscle_group_selection_date') ?? '';

    // Kiểm tra xem nhóm cơ này có bị khóa trong chu kỳ hiện tại hay không
    if (_customMuscleGroupLoopHistory.contains(groupName) && _customMuscleGroupLoopHistory.length < 3) {
      final exercises = _exerciseGroups[groupName] ?? [];
      final isCurrentlySelected = exercises.any((e) => _customSelectedExercises.contains(e));
      
      if (!isCurrentlySelected) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Nhóm $groupName đã được tập trong chu kỳ này. Hãy chọn nhóm khác!'),
              backgroundColor: AppTheme.errorRed,
            ),
          );
        }
        return;
      }
    }

    final exercises = _exerciseGroups[groupName] ?? [];
    final validExercises = exercises
        .where((e) => _isExerciseSelectableForDay(e, selectedDayDate, bmi, age))
        .toList();

    if (validExercises.isEmpty) return;

    final bool isAlreadySelected = validExercises.every((e) => _customSelectedExercises.contains(e));

    setState(() {
      _customSelectedExercises.clear(); // Chọn độc nhất 1 nhóm cơ mỗi ngày
      
      if (isAlreadySelected) {
        _isCustomSelectionActive = false;
        if (lastSelectionDate == todayStr && _customMuscleGroupLoopHistory.isNotEmpty) {
          _customMuscleGroupLoopHistory.removeLast();
        }
      } else {
        _isCustomSelectionActive = true;
        _customSelectedExercises.addAll(validExercises);

        if (lastSelectionDate == todayStr) {
          if (_customMuscleGroupLoopHistory.isNotEmpty) {
            _customMuscleGroupLoopHistory[_customMuscleGroupLoopHistory.length - 1] = groupName;
          } else {
            _customMuscleGroupLoopHistory.add(groupName);
          }
        } else {
          _customMuscleGroupLoopHistory.add(groupName);
        }
      }
    });

    final stringSelected = _customSelectedExercises.map((e) => e.name).toList();
    await prefs.setStringList('custom_selected_exercises', stringSelected);

    if (isAlreadySelected) {
      await prefs.remove('last_muscle_group_selection_date');
    } else {
      await prefs.setString('last_muscle_group_selection_date', todayStr);
    }

    if (_customMuscleGroupLoopHistory.length >= 3) {
      _customMuscleGroupLoopHistory.clear();
      await prefs.remove('last_muscle_group_selection_date');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('🎉 Tuyệt vời! Bạn đã hoàn thành chu kỳ tập 3 nhóm cơ. Nút chuyển đổi chế độ AI đã được mở khóa.'),
            backgroundColor: AppTheme.neonGreen,
          ),
        );
      }
    }
    await prefs.setStringList('custom_muscle_group_loop_history', _customMuscleGroupLoopHistory);

    if (_savedSchedule.isNotEmpty) {
      final int todayIndex = DateTime.now().weekday - 1;
      final int safeTodayIndex = 7 + todayIndex;

      final scientificTargets = _calculateScientificReps(
        _weight,
        _height,
        _age,
        _selectedGoal,
        _gender,
        activeCount: _customSelectedExercises.where((e) => !_isExerciseBlocked(e, bmi, age)).length,
      );
      final customList = _buildCustomExerciseList(scientificTargets);

      List<Map<String, dynamic>> updatedSchedule = List.from(_savedSchedule);
      updatedSchedule[safeTodayIndex]['exercises'] = customList;
      updatedSchedule[safeTodayIndex]['isRest'] = false;

      await _saveScheduleLocallyAndDb(updatedSchedule);
    }
  }

  Widget _buildModeSelector() {
    final bool isLocked = _customMuscleGroupLoopHistory.isNotEmpty && _customMuscleGroupLoopHistory.length < 3;
    final int currentStep = _customMuscleGroupLoopHistory.length;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: (isLocked || _hasStartedTodayWorkout())
                      ? null
                      : () => _updateActiveMode(false),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      color: !_isCustomSelectionActive
                          ? AppTheme.neonGreen.withValues(alpha: 0.15)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(12),
                      border: !_isCustomSelectionActive
                          ? Border.all(color: AppTheme.neonGreen.withValues(alpha: 0.4))
                          : null,
                    ),
                    child: Center(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.auto_awesome,
                            size: 14,
                            color: !_isCustomSelectionActive
                                ? AppTheme.neonGreen
                                : Colors.grey,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'HLV AI ĐỀ XUẤT',
                            style: TextStyle(
                              color: !_isCustomSelectionActive
                                  ? AppTheme.neonGreen
                                  : Colors.grey,
                              fontWeight: FontWeight.bold,
                              fontSize: 11.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: GestureDetector(
                  onTap: (isLocked || _hasStartedTodayWorkout())
                      ? null
                      : () => _updateActiveMode(true),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      color: _isCustomSelectionActive
                          ? AppTheme.neonBlue.withValues(alpha: 0.15)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(12),
                      border: _isCustomSelectionActive
                          ? Border.all(color: AppTheme.neonBlue.withValues(alpha: 0.4))
                          : null,
                    ),
                    child: Center(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.tune,
                            size: 14,
                            color: _isCustomSelectionActive
                                ? AppTheme.neonBlue
                                : Colors.grey,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'TỰ CHỌN NHÓM CƠ',
                            style: TextStyle(
                              color: _isCustomSelectionActive
                                  ? AppTheme.neonBlue
                                  : Colors.grey,
                              fontWeight: FontWeight.bold,
                              fontSize: 11.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          if (isLocked) ...[
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              child: Row(
                children: [
                  const Icon(
                    Icons.lock_clock,
                    size: 14,
                    color: Colors.orangeAccent,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Chu kỳ tự chọn đang khóa (Buổi $currentStep/3). Tập đủ 3 nhóm để mở lại chế độ AI.',
                      style: const TextStyle(
                        color: Colors.orangeAccent,
                        fontSize: 10.5,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ] else if (_hasStartedTodayWorkout()) ...[
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              child: Row(
                children: [
                  const Icon(
                    Icons.lock_outline_rounded,
                    size: 14,
                    color: AppTheme.errorRed,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Bạn đã bắt đầu tập luyện hôm nay. Chế độ tập đã khóa.',
                      style: const TextStyle(
                        color: AppTheme.errorRed,
                        fontSize: 10.5,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _updateActiveMode(bool isCustom) async {
    if (_hasStartedTodayWorkout()) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Bạn đã bắt đầu tập luyện ngày hôm nay. Không thể thay đổi chế độ tập!'),
            backgroundColor: AppTheme.errorRed,
          ),
        );
      }
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('is_custom_selection_active', isCustom);
    
    setState(() {
      _isCustomSelectionActive = isCustom;
    });

    if (!isCustom) {
      _customSelectedExercises.clear();
      await prefs.remove('custom_selected_exercises');
      
      if (_savedSchedule.isNotEmpty) {
        final int todayIndex = DateTime.now().weekday - 1;
        final int safeTodayIndex = 7 + todayIndex;
        
        final double bmi = _weight / ((_height / 100) * (_height / 100));
        final generated = _generateAdaptiveSchedule(_selectedGoal, bmi, _age);
        
        List<Map<String, dynamic>> updatedSchedule = List.from(_savedSchedule);
        updatedSchedule[safeTodayIndex]['exercises'] = generated[todayIndex]['exercises'];
        updatedSchedule[safeTodayIndex]['isRest'] = generated[todayIndex]['isRest'];
        
        await _saveScheduleLocallyAndDb(updatedSchedule);
      }
    } else {
      if (_savedSchedule.isNotEmpty) {
        final int todayIndex = DateTime.now().weekday - 1;
        final int safeTodayIndex = 7 + todayIndex;
        
        if (_customSelectedExercises.isEmpty) {
          List<Map<String, dynamic>> updatedSchedule = List.from(_savedSchedule);
          updatedSchedule[safeTodayIndex]['exercises'] = [];
          updatedSchedule[safeTodayIndex]['isRest'] = false;
          await _saveScheduleLocallyAndDb(updatedSchedule);
        } else {
          _enforceMuscleGroupLoopForToday(safeTodayIndex);
        }
      }
    }
  }

  Future<void> _enforceMuscleGroupLoopForToday(int safeTodayIndex) async {
    final prefs = await SharedPreferences.getInstance();
    if (_customMuscleGroupLoopHistory.length == 2) {
      String remainingGroup = '';
      for (final g in _exerciseGroups.keys) {
        if (!_customMuscleGroupLoopHistory.contains(g)) {
          remainingGroup = g;
          break;
        }
      }
      
      if (remainingGroup.isNotEmpty) {
        final exercises = _exerciseGroups[remainingGroup] ?? [];
        final bmi = _weight / ((_height / 100) * (_height / 100));
        final valid = exercises.where((e) => !_isExerciseBlocked(e, bmi, _age)).toList();
        
        _customSelectedExercises.clear();
        _customSelectedExercises.addAll(valid);
        
        final stringList = _customSelectedExercises.map((e) => e.name).toList();
        await prefs.setStringList('custom_selected_exercises', stringList);

        _customMuscleGroupLoopHistory.add(remainingGroup);
        if (_customMuscleGroupLoopHistory.length >= 3) {
          _customMuscleGroupLoopHistory.clear();
          await prefs.remove('last_muscle_group_selection_date');
        }
        await prefs.setStringList('custom_muscle_group_loop_history', _customMuscleGroupLoopHistory);

        final scientificTargets = _calculateScientificReps(
          _weight,
          _height,
          _age,
          _selectedGoal,
          _gender,
          activeCount: valid.length,
        );
        final customList = _buildCustomExerciseList(scientificTargets);
        
        List<Map<String, dynamic>> updatedSchedule = List.from(_savedSchedule);
        updatedSchedule[safeTodayIndex]['exercises'] = customList;
        updatedSchedule[safeTodayIndex]['isRest'] = false;
        
        await _saveScheduleLocallyAndDb(updatedSchedule);
      }
    }
  }

  List<Map<String, dynamic>> _buildCustomExerciseList(
    Map<ExerciseType, int> scientificTargets,
  ) {
    return _customSelectedExercises.map((type) {
      final ex = ExerciseDetail.defaultExercises.firstWhere(
        (e) => e.type == type,
      );
      String groupName = '';
      for (final entry in _exerciseGroups.entries) {
        if (entry.value.contains(type)) {
          groupName = entry.key;
          break;
        }
      }
      return {
        'type': type,
        'reason': '${ex.name} - ${_groupReasons[groupName] ?? ''}',
      };
    }).toList();
  }

  Widget _buildExerciseGroupSelector(
    double bmi,
    int age,
    DateTime selectedDayDate,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'CHỌN NHÓM CƠ MUỐN TẬP HÔM NAY',
          style: TextStyle(
            color: Colors.white70,
            fontSize: 10,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: _exerciseGroups.keys.map((groupName) {
            final exercises = _exerciseGroups[groupName] ?? [];
            final availableExercises = exercises
                .where((e) => _isExerciseSelectableForDay(e, selectedDayDate, bmi, age))
                .toList();

            final allSelected = availableExercises.isNotEmpty && availableExercises.every(
              (e) => _customSelectedExercises.contains(e),
            );

            final bool isGroupLocked = _customMuscleGroupLoopHistory.contains(groupName) && 
                                       _customMuscleGroupLoopHistory.length < 3 && 
                                       !allSelected;

            final bool isForcedGroup = _customMuscleGroupLoopHistory.length == 2 && 
                                       !_customMuscleGroupLoopHistory.contains(groupName);

            Color btnBgColor;
            Color btnBorderColor;
            Color textColor;
            IconData? icon;

            if (isGroupLocked || (_hasStartedTodayWorkout() && !allSelected)) {
              btnBgColor = Colors.black.withValues(alpha: 0.5);
              btnBorderColor = Colors.white.withValues(alpha: 0.03);
              textColor = Colors.white.withValues(alpha: 0.25);
              icon = Icons.lock_outline;
            } else if (isForcedGroup) {
              btnBgColor = AppTheme.neonGreen.withValues(alpha: 0.05);
              btnBorderColor = AppTheme.neonGreen.withValues(alpha: 0.3);
              textColor = AppTheme.neonGreen;
              icon = Icons.star_border_purple500_rounded;
            } else if (allSelected) {
              btnBgColor = AppTheme.neonBlue.withValues(alpha: 0.15);
              btnBorderColor = AppTheme.neonBlue;
              textColor = Colors.white;
              icon = Icons.check_circle_outline;
            } else {
              btnBgColor = Colors.white.withValues(alpha: 0.04);
              btnBorderColor = Colors.white.withValues(alpha: 0.1);
              textColor = Colors.white70;
            }

            return Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4.0),
                child: GestureDetector(
                  onTap: (availableExercises.isEmpty || isGroupLocked || isForcedGroup || _hasStartedTodayWorkout())
                      ? null
                      : () => _toggleExerciseGroup(
                            groupName,
                            bmi,
                            age,
                            selectedDayDate,
                          ),
                  child: Container(
                    height: 52,
                    decoration: BoxDecoration(
                      color: btnBgColor,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: btnBorderColor, width: 1.2),
                      boxShadow: allSelected
                          ? [
                              BoxShadow(
                                color: AppTheme.neonBlue.withValues(alpha: 0.15),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              )
                            ]
                          : null,
                    ),
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          if (icon != null) ...[
                            Icon(icon, size: 12, color: textColor),
                            const SizedBox(height: 3),
                          ],
                          Text(
                            groupName,
                            style: TextStyle(
                              color: textColor,
                              fontSize: 10.5,
                              fontWeight: FontWeight.bold,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
        if (_customMuscleGroupLoopHistory.length == 2) ...[
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4.0),
            child: Row(
              children: [
                const Icon(
                  Icons.star_purple500_rounded,
                  size: 13,
                  color: AppTheme.neonGreen,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Chu kỳ đang bắt buộc nhóm cơ cuối cùng để hoàn thành vòng lặp 3 ngày.',
                    style: TextStyle(
                      color: AppTheme.neonGreen.withValues(alpha: 0.9),
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
        if (_hasStartedTodayWorkout()) ...[
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4.0),
            child: Row(
              children: [
                const Icon(
                  Icons.lock_outline_rounded,
                  size: 13,
                  color: AppTheme.errorRed,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Bạn đã bắt đầu tập luyện hôm nay. Nhóm cơ đã tập được khóa cố định.',
                    style: TextStyle(
                      color: AppTheme.errorRed.withValues(alpha: 0.9),
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  List<Map<String, dynamic>> _postProcessAdaptiveSchedule(List<Map<String, dynamic>> rawSchedule) {
    // rawSchedule có 7 phần tử (Day 1 -> Day 7). Nhân bản thành 3 tuần (21 phần tử)
    final List<Map<String, dynamic>> raw21 = [];
    for (int i = 0; i < 7; i++) {
      final dayCopy = Map<String, dynamic>.from(rawSchedule[i]);
      dayCopy['day'] = i + 1;
      dayCopy['weekLabel'] = 'Tuần trước';
      raw21.add(dayCopy);
    }
    for (int i = 0; i < 7; i++) {
      final dayCopy = Map<String, dynamic>.from(rawSchedule[i]);
      dayCopy['day'] = i + 8;
      dayCopy['weekLabel'] = 'Tuần này';
      raw21.add(dayCopy);
    }
    for (int i = 0; i < 7; i++) {
      final dayCopy = Map<String, dynamic>.from(rawSchedule[i]);
      dayCopy['day'] = i + 15;
      dayCopy['weekLabel'] = 'Tuần sau';
      raw21.add(dayCopy);
    }
    
    return raw21;
  }

  Future<void> _refreshTodayDraftWorkout() async {
    final draft = await _workoutDraftService.getTodayDraftWorkout();
    if (mounted) {
      setState(() {
        _todayDraftWorkout = draft;
      });
    }
  }

  Future<void> _loadMealLogsForDay(DateTime day) async {
    final dayKey = _getDayKey(day);
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('meal_logs_$dayKey');

    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw) as List<dynamic>;
        if (mounted) {
          setState(() {
            _todayMealLogs = decoded
                .map((e) => Map<String, dynamic>.from(e as Map))
                .toList();
          });
        }
      } catch (e) {
        debugPrint('Lỗi tải nhật ký ăn uống: $e');
        if (mounted) {
          setState(() {
            _todayMealLogs = [];
          });
        }
      }
    } else {
      if (mounted) {
        setState(() {
          _todayMealLogs = [];
        });
      }
    }
  }

  Future<void> _saveMealLogsForDay(DateTime day) async {
    final dayKey = _getDayKey(day);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('meal_logs_$dayKey', jsonEncode(_todayMealLogs));
  }

  bool get _isSupabaseInitialized {
    try {
      Supabase.instance.client;
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _loadUserProfile() async {
    if (!_isSupabaseInitialized) {
      setState(() {
        _weight = 65.0;
        _height = 170.0;
        _age = 25;
        _userName = 'Khách (Offline)';
        _isLoading = false;
      });
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final profile = await _authService.getCurrentUserProfile();
      if (profile != null && mounted) {
        setState(() {
          _userName = profile['ho_ten'] ?? 'Trainer';
          _weight = (profile['can_nang'] as num?)?.toDouble() ?? 0.0;
          _height = (profile['chieu_cao'] as num?)?.toDouble() ?? 0.0;
          _age = (profile['tuoi'] as num?)?.toInt() ?? 0;
          _gender = profile['gioi_tinh'] ?? 'male';

          if (_weight == 0.0) _weight = 65.0;
          if (_height == 0.0) _height = 170.0;
          if (_age == 0) _age = 25;

          final String? dbGoal = profile['muc_tieu'] ?? profile['fitness_goal'];
          double bmi = _weight / ((_height / 100) * (_height / 100));

          if (bmi >= 25.0) {
            _selectedGoal = 'lose';
          } else if (bmi < 18.5) {
            _selectedGoal = 'build';
          } else {
            if (dbGoal == 'maintain' || dbGoal == 'build') {
              _selectedGoal = dbGoal!;
            } else {
              _selectedGoal = 'maintain';
            }
          }

          if (_selectedGoal != dbGoal) {
            _updateGoal(_selectedGoal, currentBmi: bmi);
          }
        });
      }
    } catch (e) {
      debugPrint('Lỗi tải hồ sơ đề xuất: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _updatePhysicalStats(
    double newHeight,
    double newWeight,
    int newAge,
    String newGender,
  ) async {
    setState(() {
      _isLoading = true;
    });

    try {
      double newBmi = newHeight > 0
          ? newWeight / ((newHeight / 100) * (newHeight / 100))
          : 0.0;
      String nextGoal = _selectedGoal;
      if (!isGoalAllowedForBmi(_selectedGoal, newBmi)) {
        if (newBmi >= 25.0) {
          nextGoal = 'lose';
        } else if (newBmi < 18.5) {
          nextGoal = 'build';
        } else {
          nextGoal = 'maintain';
        }
      }

      if (_isSupabaseInitialized) {
        final client = Supabase.instance.client;
        final userId = client.auth.currentUser?.id;
        if (userId != null) {
          await client
              .from('ho_so_nguoi_dung')
              .update({
                'chieu_cao': newHeight,
                'can_nang': newWeight,
                'tuoi': newAge,
                'gioi_tinh': newGender,
              })
              .eq('ma_nguoi_dung', userId);
        }
      }

      setState(() {
        _height = newHeight;
        _weight = newWeight;
        _age = newAge;
        _gender = newGender;
      });

      if (nextGoal != _selectedGoal) {
        await _updateGoal(nextGoal, currentBmi: newBmi);
      } else {
        await _triggerScheduleUpdateFromToday(newBmi);
      }
    } catch (e) {
      debugPrint('Lỗi cập nhật chỉ số thể chất: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Lỗi cập nhật: $e')));
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _updateGoal(String newGoal, {double? currentBmi}) async {
    setState(() {
      _selectedGoal = newGoal;
    });

    double bmi =
        currentBmi ??
        (_height > 0 ? _weight / ((_height / 100) * (_height / 100)) : 0.0);
    await _triggerScheduleUpdateFromToday(bmi);

    if (!_isSupabaseInitialized) return;
    try {
      final client = Supabase.instance.client;
      final userId = client.auth.currentUser?.id;
      if (userId != null) {
        await client
            .from('ho_so_nguoi_dung')
            .update({'muc_tieu': newGoal})
            .eq('ma_nguoi_dung', userId);
      }
    } catch (e) {
      debugPrint('Lỗi đồng bộ mục tiêu lên DB: $e');
    }
  }

  String _getDayKey(DateTime day) {
    final year = day.year.toString();
    final month = day.month.toString().padLeft(2, '0');
    final dayValue = day.day.toString().padLeft(2, '0');
    return '$year-$month-$dayValue';
  }

  DateTime _getSelectedDayDate(int index) {
    final now = DateTime.now();
    final todayIndex = now.weekday - 1;
    final startOfToday = DateTime(now.year, now.month, now.day);
    final mondayOfThisWeek = startOfToday.subtract(Duration(days: todayIndex));
    return mondayOfThisWeek.add(Duration(days: index - 7));
  }

  bool _isDayWorkoutCompleted(int index, List<Map<String, dynamic>> schedule) {
    if (index >= schedule.length) return false;
    final dayDate = _getSelectedDayDate(index);
    final selectedDayData = schedule[index];
    final List<dynamic> currentExercises =
        selectedDayData['exercises'] as List<dynamic>? ?? [];
    final bool isRest = selectedDayData['isRest'] as bool? ?? false;

    if (isRest) return true;
    if (currentExercises.isEmpty) return false;

    for (var rec in currentExercises) {
      final ExerciseType type = rec['type'] as ExerciseType;
      if (!_isExerciseCompletedForDay(type, dayDate)) {
        return false;
      }
    }
    return true;
  }

  bool _isExerciseCompletedForDay(ExerciseType type, DateTime day) {
    final dayKey = _getDayKey(day);
    final completionKeys =
        _completedExerciseKeysByDay[dayKey] ?? const <String>{};
    return completionKeys.contains(type.name);
  }

  bool _hasStartedTodayWorkout() {
    if (_savedSchedule.isEmpty) return false;
    final int todayIndex = DateTime.now().weekday - 1;
    final int safeTodayIndex = 7 + todayIndex;
    if (safeTodayIndex >= _savedSchedule.length) return false;
    final todayData = _savedSchedule[safeTodayIndex];
    final exercises = todayData['exercises'] as List? ?? [];
    final selectedDate = _getSelectedDayDate(safeTodayIndex);
    
    for (final ex in exercises) {
      final type = ex['type'] as ExerciseType;
      if (_isExerciseCompletedForDay(type, selectedDate)) {
        return true;
      }
    }
    return false;
  }

  Future<void> _loadCompletedExercisesForDay(DateTime day) async {
    if (!_isSupabaseInitialized) return;
    try {
      final completedRecords = await DatabaseService()
          .getCompletedExerciseRecordsForDate(day);
      final dayKey = _getDayKey(day);
      final Set<String> completedExerciseNames = {};

      for (final row in completedRecords) {
        final String? loaiBaiTap =
            row['loai_bai_tap'] as String? ?? row['source_tag'] as String?;
        final String? maBaiTapRieng =
            row['ma_bai_tap_rieng'] as String? ?? row['exercise_id'] as String?;
        final int soLanTap =
            (row['so_lan_tap'] as num?)?.toInt() ??
            (row['reps_count'] as num?)?.toInt() ??
            0;

        final bool isRecommended =
            loaiBaiTap != null &&
            (loaiBaiTap.toLowerCase() == 'recommended' ||
                loaiBaiTap.toLowerCase().startsWith('recommended:'));

        String exerciseName = maBaiTapRieng ?? '';

        if (isRecommended && exerciseName.isNotEmpty && soLanTap > 0) {
          final exerciseType = _exerciseTypeFromName(exerciseName);
          if (exerciseType != null) {
            completedExerciseNames.add(exerciseType.name);
          }
        }
      }

      if (mounted) {
        setState(() {
          _completedExerciseKeysByDay[dayKey] = completedExerciseNames;
        });
      }
    } catch (e) {
      debugPrint('Lỗi tải lịch sử hoàn thành bài tập: $e');
    }
  }

  Future<void> _toggleExerciseCompletedForDay(
    ExerciseType type,
    DateTime day,
    int targetCount, {
    bool isManual = true,
  }) async {
    final dayKey = _getDayKey(day);
    final completedForDay = _completedExerciseKeysByDay.putIfAbsent(
      dayKey,
      () => <String>{},
    );
    final exerciseName = type.name;

    if (completedForDay.contains(exerciseName)) {
      completedForDay.remove(exerciseName);
    } else {
      completedForDay.add(exerciseName);
      if (isManual) {
        try {
          await DatabaseService().saveWorkoutResult(
            exerciseType: type.name,
            repsCount: targetCount,
            durationSeconds:
                type == ExerciseType.plank || type == ExerciseType.jumping_jack
                ? targetCount
                : 45,
            caloriesBurned: type == ExerciseType.plank
                ? targetCount * 0.1
                : targetCount * 0.4,
            incorrectPostures: 0,
            sourceTag: 'recommended',
          );
        } catch (e) {
          debugPrint('Lỗi đồng bộ tick bài tập: $e');
        }
      }
    }
    if (mounted) setState(() {});
  }

  ExerciseType? _exerciseTypeFromName(String name) {
    for (final exercise in ExerciseDetail.defaultExercises) {
      if (exercise.type.name == name) {
        return exercise.type;
      }
    }
    return null;
  }

  void _showEditStatsDialog() {
    final heightController = TextEditingController(
      text: _height > 0 ? _height.toStringAsFixed(0) : '170',
    );
    final weightController = TextEditingController(
      text: _weight > 0 ? _weight.toStringAsFixed(0) : '60',
    );
    final ageController = TextEditingController(
      text: _age > 0 ? _age.toString() : '25',
    );
    String dialogGender = _gender;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: AppTheme.cardBackground,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: const Center(
            child: Text(
              'CẬP NHẬT THỂ TRẠNG',
              style: TextStyle(
                color: AppTheme.neonGreen,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: heightController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Chiều cao (cm)',
                    labelStyle: TextStyle(color: Colors.grey),
                    focusedBorder: UnderlineInputBorder(
                      borderSide: BorderSide(color: AppTheme.neonGreen),
                    ),
                  ),
                  style: const TextStyle(color: Colors.white),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: weightController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Cân nặng (kg)',
                    labelStyle: TextStyle(color: Colors.grey),
                    focusedBorder: UnderlineInputBorder(
                      borderSide: BorderSide(color: AppTheme.neonGreen),
                    ),
                  ),
                  style: const TextStyle(color: Colors.white),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: ageController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Tuổi',
                    labelStyle: TextStyle(color: Colors.grey),
                    focusedBorder: UnderlineInputBorder(
                      borderSide: BorderSide(color: AppTheme.neonGreen),
                    ),
                  ),
                  style: const TextStyle(color: Colors.white),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: dialogGender,
                  dropdownColor: AppTheme.cardBackground,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    labelText: 'Giới tính',
                    labelStyle: TextStyle(color: Colors.grey),
                    focusedBorder: UnderlineInputBorder(
                      borderSide: BorderSide(color: AppTheme.neonGreen),
                    ),
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: 'male',
                      child: Text(
                        'Nam (Male)',
                        style: TextStyle(color: Colors.white),
                      ),
                    ),
                    DropdownMenuItem(
                      value: 'female',
                      child: Text(
                        'Nữ (Female)',
                        style: TextStyle(color: Colors.white),
                      ),
                    ),
                  ],
                  onChanged: (val) {
                    if (val != null) {
                      setDialogState(() {
                        dialogGender = val;
                      });
                    }
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Hủy', style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              onPressed: () {
                final double? h = double.tryParse(heightController.text);
                final double? w = double.tryParse(weightController.text);
                final int? a = int.tryParse(ageController.text);
                if (h != null && w != null && a != null) {
                  Navigator.pop(context);
                  _updatePhysicalStats(h, w, a, dialogGender);
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.neonGreen,
              ),
              child: const Text(
                'Lưu',
                style: TextStyle(
                  color: Colors.black,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Map<ExerciseType, int> _calculateScientificReps(
    double weight,
    double height,
    int age,
    String goal,
    String gender, {
    int activeCount = 4,
  }) {
    double bmi = weight / ((height / 100) * (height / 100));
    double bmr = 0.0;
    if (gender.toLowerCase() == 'female') {
      bmr = (10 * weight) + (6.25 * height) - (5 * age) - 161;
    } else {
      bmr = (10 * weight) + (6.25 * height) - (5 * age) + 5;
    }
    if (bmr < 1000) bmr = 1000;

    double activityFactor = 1.2;
    if (bmi < 18.5) {
      activityFactor = 1.3;
    } else if (bmi < 25.0) {
      activityFactor = (bmr > 1500) ? 1.425 : 1.375;
    } else if (bmi < 30.0) {
      activityFactor = 1.3;
    } else {
      activityFactor = 1.2;
    }

    double tdee = bmr * activityFactor;
    double targetDailyCalories = tdee;

    if (bmi < 18.5) {
      targetDailyCalories = tdee + (tdee * 0.15);
    } else if (bmi < 25.0) {
      if (goal == 'lose') {
        targetDailyCalories = tdee - (tdee * 0.15);
      } else if (goal == 'build') {
        targetDailyCalories = tdee + (tdee * 0.10);
      } else {
        targetDailyCalories = tdee;
      }
    } else if (bmi < 30.0) {
      targetDailyCalories = tdee - (tdee * 0.15);
    } else {
      targetDailyCalories = tdee - (tdee * 0.20);
    }

    if (targetDailyCalories < bmr) targetDailyCalories = bmr;

    double targetWorkoutCalories = 0.0;
    if (bmi >= 25.0 || goal == 'lose') {
      targetWorkoutCalories = tdee * 0.12;
    } else if (goal == 'build') {
      targetWorkoutCalories = tdee * 0.08;
    } else {
      targetWorkoutCalories = tdee * 0.06;
    }

    targetWorkoutCalories = targetWorkoutCalories.clamp(80, 350);
    final double caloriesPerExercise = targetWorkoutCalories / (activeCount > 0 ? activeCount : 4);
    final Map<ExerciseType, int> computedTargets = {};
    double weightFactor = weight / 70.0;

    for (final exercise in ExerciseDetail.defaultExercises) {
      if (exercise.isDurationBased) {
        double personalizedCpm = exercise.caloriesPerMin * weightFactor;
        double sec =
            (caloriesPerExercise * 60) /
            (personalizedCpm > 0 ? personalizedCpm : 1);
        int roundedSec = ((sec / 10).round() * 10).clamp(30, 240);
        if (bmi >= 25.0) roundedSec = roundedSec.clamp(30, 120);
        if (gender.toLowerCase() == 'female') {
          roundedSec = (roundedSec * 0.85).round();
        }
        computedTargets[exercise.type] = roundedSec;
      } else {
        double caloriesPerRep = _getCaloPerRep(exercise.type) * weightFactor;
        double reps =
            caloriesPerExercise / (caloriesPerRep > 0 ? caloriesPerRep : 1);
        int roundedReps = ((reps / 5).round() * 5);
        if (gender.toLowerCase() == 'female') {
          roundedReps = (roundedReps * 0.85).round();
        }

        if (bmi >= 25.0) {
          if (exercise.type == ExerciseType.burpee) {
            roundedReps = roundedReps.clamp(5, 30);
          } else if (exercise.type == ExerciseType.push_up) {
            roundedReps = roundedReps.clamp(5, 40);
          } else if (exercise.type == ExerciseType.squat) {
            roundedReps = roundedReps.clamp(5, 50);
          } else if (exercise.type == ExerciseType.walking_lunge) {
            roundedReps = roundedReps.clamp(5, 30);
          } else {
            roundedReps = roundedReps.clamp(20, 80);
          }
        } else {
          if (exercise.type == ExerciseType.burpee) {
            roundedReps = roundedReps.clamp(20, 120);
          } else if (exercise.type == ExerciseType.push_up) {
            roundedReps = roundedReps.clamp(40, 160);
          } else if (exercise.type == ExerciseType.squat) {
            roundedReps = roundedReps.clamp(48, 160);
          } else if (exercise.type == ExerciseType.walking_lunge) {
            roundedReps = roundedReps.clamp(40, 160);
          } else {
            roundedReps = roundedReps.clamp(48, 160);
          }
        }
        computedTargets[exercise.type] = roundedReps;
      }
    }
    return computedTargets;
  }

  double _getCaloPerRep(ExerciseType type) => switch (type) {
    ExerciseType.burpee => 0.8,
    ExerciseType.push_up => 0.35,
    ExerciseType.walking_lunge => 0.4,
    ExerciseType.squat => 0.35,
    ExerciseType.jumping_jack => 0.25,
    ExerciseType.plank => 0.0,
  };

  List<Map<String, dynamic>> _generateAdaptiveSchedule(
    String goal,
    double bmi,
    int age,
  ) {
    if (goal == 'lose') {
      return [
        {
          'day': 1,
          'title': 'Đốt mỡ khởi động',
          'isRest': false,
          'exercises': [
            {
              'type': ExerciseType.jumping_jack,
              'reason':
                  'Nhảy Jumping Jack nhịp nhàng để làm nóng cơ thể và kích hoạt tuần hoàn tim mạch (Toàn thân).',
            },
            {
              'type': ExerciseType.burpee,
              'reason':
                  'Burpee bộc phát giúp đẩy tối đa hiệu suất tiêu hao năng lượng trong ngày khởi đầu (Toàn thân).',
            },
          ],
        },
        {
          'day': 2,
          'title': 'Kích hoạt bụng & Sức mạnh thân trên',
          'isRest': false,
          'exercises': [
            {
              'type': ExerciseType.plank,
              'reason':
                  'Plank để củng cố sức mạnh nhóm cơ core trung tâm bụng lưng (Thân trên).',
            },
            {
              'type': ExerciseType.push_up,
              'reason':
                  'Chống đẩy duy trì phom ngực và vai săn chắc (Thân trên).',
            },
          ],
        },
        {
          'day': 3,
          'title': 'Nghỉ ngơi phục hồi',
          'isRest': true,
          'reason':
              'Hãy thực hiện các động tác giãn cơ nhẹ nhàng hoặc đi bộ thư giãn để giải phóng axit lactic và giúp cơ bắp hồi phục.',
        },
        {
          'day': 4,
          'title': 'Săn chắc chân mông',
          'isRest': false,
          'exercises': [
            {
              'type': ExerciseType.squat,
              'reason':
                  'Squat tăng cường sức mạnh đùi mông và cải thiện tính thăng bằng (Thân dưới).',
            },
            {
              'type': ExerciseType.walking_lunge,
              'reason':
                  'Lunge bước đi săn chắc đùi mông và cải thiện tính thăng bằng khớp hông (Thân dưới).',
            },
          ],
        },
        {
          'day': 5,
          'title': 'Sức bền & Bộc phát',
          'isRest': false,
          'exercises': [
            {
              'type': ExerciseType.jumping_jack,
              'reason':
                  'Nhảy Jumping Jack nhịp nhàng để làm nóng cơ thể và kích hoạt tuần hoàn tim mạch (Toàn thân).',
            },
            {
              'type': ExerciseType.burpee,
              'reason':
                  'Burpee cường độ cao giúp tối ưu hóa calo thâm hụt (Toàn thân).',
            },
          ],
        },
        {
          'day': 6,
          'title': 'Kích hoạt bụng & Sức mạnh thân trên',
          'isRest': false,
          'exercises': [
            {
              'type': ExerciseType.plank,
              'reason':
                  'Thử thách Plank giữ thẳng lưng giúp định hình vòng eo thon nhỏ (Thân trên).',
            },
            {
              'type': ExerciseType.push_up,
              'reason':
                  'Chống đẩy duy trì phom ngực và vai săn chắc (Thân trên).',
            },
          ],
        },
        {
          'day': 7,
          'title': 'Nghỉ ngơi phục hồi',
          'isRest': true,
          'reason':
              'Hoàn thành chu kỳ 7 ngày tập luyện. Hãy uống đủ nước, ăn đủ chất và ngủ sâu để chuẩn bị cho chu kỳ tiếp theo hiệu quả hơn!',
        },
      ];
    } else if (goal == 'build') {
      return [
        {
          'day': 1,
          'title': 'Sức mạnh Ngực & Vai',
          'isRest': false,
          'exercises': [
            {
              'type': ExerciseType.push_up,
              'reason':
                  'Chống đẩy tập trung kích thích phát triển nhóm cơ ngực lớn, vai trước và tay sau (Thân trên).',
            },
            {
              'type': ExerciseType.plank,
              'reason':
                  'Plank tăng độ vững chãi cho core bụng để chịu lực cơ thể tốt hơn (Thân trên).',
            },
          ],
        },
        {
          'day': 2,
          'title': 'Phát triển Mông Đùi',
          'isRest': false,
          'exercises': [
            {
              'type': ExerciseType.squat,
              'reason':
                  'Squat kích hoạt sản sinh hormone tăng trưởng tự nhiên để phát triển nhóm cơ lớn nhất cơ thể (Thân dưới).',
            },
            {
              'type': ExerciseType.walking_lunge,
              'reason':
                  'Walking Lunge tăng sức mạnh độc lập từng chân và cải thiện tính linh hoạt khớp hông (Thân dưới).',
            },
          ],
        },
        {
          'day': 3,
          'title': 'Nghỉ ngơi phục hồi cơ',
          'isRest': true,
          'reason':
              'Cơ bắp cần thời gian nghỉ ngơi để bù đắp sợi cơ bị tổn thương sau những ngày tập nặng. Hãy ngủ đủ giấc!',
        },
        {
          'day': 4,
          'title': 'Thể lực & Bộc phát',
          'isRest': false,
          'exercises': [
            {
              'type': ExerciseType.burpee,
              'reason':
                  'Burpee thử thách sức bền cơ bắp bộc phát cường độ cao toàn diện (Toàn thân).',
            },
            {
              'type': ExerciseType.jumping_jack,
              'reason':
                  'Nhảy Jumping Jack nhịp nhàng để làm nóng cơ thể và kích hoạt tuần hoàn tim mạch (Toàn thân).',
            },
          ],
        },
        {
          'day': 5,
          'title': 'Kích hoạt bụng & Sức mạnh thân trên',
          'isRest': false,
          'exercises': [
            {
              'type': ExerciseType.plank,
              'reason':
                  'Plank tăng sức bền tĩnh cho cột sống và nhóm cơ sườn chậu (Thân trên).',
            },
            {
              'type': ExerciseType.push_up,
              'reason':
                  'Chống đẩy tập trung kích thích phát triển nhóm cơ ngực lớn, vai trước và tay sau (Thân trên).',
            },
          ],
        },
        {
          'day': 6,
          'title': 'Sức bền ',
          'isRest': false,
          'exercises': [
            {
              'type': ExerciseType.burpee,
              'reason':
                  'Burpee thử thách sức bền cơ bắp bộc phát cường độ cao toàn diện (Toàn thân).',
            },
            {
              'type': ExerciseType.jumping_jack,
              'reason':
                  'Jumping Jack kích hoạt bơm máu toàn thân tăng tốc độ chuyển hóa dưỡng chất (Toàn thân).',
            },
          ],
        },
        {
          'day': 7,
          'title': 'Nghỉ ngơi phục hồi cơ',
          'isRest': true,
          'reason':
              'Chúc mừng bạn đã hoàn thành chu kỳ tập cơ! Hãy ăn đủ đạm, bổ sung nước và chuẩn bị thể lực tốt nhất.',
        },
      ];
    } else {
      return [
        {
          'day': 1,
          'title': 'Kích hoạt bụng & Sức mạnh thân trên',
          'isRest': false,
          'exercises': [
            {
              'type': ExerciseType.plank,
              'reason':
                  'Plank siết eo nhẹ nhàng duy trì bụng phẳng và tư thế đứng thẳng đẹp mắt (Thân trên).',
            },
            {
              'type': ExerciseType.push_up,
              'reason':
                  'Chống đẩy tập trung kích thích phát triển nhóm cơ ngực lớn, vai trước và tay sau (Thân trên).',
            },
          ],
        },
        {
          'day': 2,
          'title': 'Săn chắc Thân dưới',
          'isRest': false,
          'exercises': [
            {
              'type': ExerciseType.squat,
              'reason':
                  'Squat vừa sức duy trì cơ đùi mông săn gọn và linh hoạt ổ khớp gối (Thân dưới).',
            },
            {
              'type': ExerciseType.walking_lunge,
              'reason':
                  'Walking Lunge tăng độ thăng bằng di động cho cơ khớp hông háng (Thân dưới).',
            },
          ],
        },
        {
          'day': 3,
          'title': 'Nghỉ ngơi phục hồi',
          'isRest': true,
          'reason':
              'Một ngày thư giãn cơ thể. Hãy đi bộ nhẹ nhàng hoặc thực hiện yoga giãn cơ tại nhà.',
        },
        {
          'day': 4,
          'title': 'Sức bền toàn diện',
          'isRest': false,
          'exercises': [
            {
              'type': ExerciseType.burpee,
              'reason':
                  'Burpee thử thách sức bền cơ bắp bộc phát cường độ cao toàn diện (Toàn thân).',
            },
            {
              'type': ExerciseType.jumping_jack,
              'reason':
                  'Jumping Jack kích hoạt bơm máu toàn thân tăng tốc độ chuyển hóa dưỡng chất (Toàn thân).',
            },
          ],
        },
        {
          'day': 5,
          'title': 'Kích hoạt bụng & Sức mạnh thân trên',
          'isRest': false,
          'exercises': [
            {
              'type': ExerciseType.push_up,
              'reason':
                  'Chống đẩy tập trung kích thích phát triển nhóm cơ ngực lớn, vai trước và tay sau (Thân trên).',
            },
            {
              'type': ExerciseType.plank,
              'reason':
                  'Plank giữ vững liên kết cột sống lưng tránh đau mỏi do ngồi văn phòng nhiều (Thân trên).',
            },
          ],
        },
        {
          'day': 6,
          'title': 'Sức mạnh thân dưới',
          'isRest': false,
          'exercises': [
            {
              'type': ExerciseType.walking_lunge,
              'reason':
                  'Lunge bước đi nhẹ nhàng làm thon gọn bắp đùi mông (Thân dưới).',
            },
            {
              'type': ExerciseType.squat,
              'reason':
                  'Squat tăng cường sức mạnh đùi mông và cải thiện tính thăng bằng (Thân dưới).',
            },
          ],
        },
        {
          'day': 7,
          'title': 'Nghỉ ngơi phục hồi',
          'isRest': true,
          'reason':
              'Hoàn thành tuần lễ duy trì vóc dáng! Hãy tiếp tục duy trì chế độ dinh dưỡng giàu xơ và ngủ ngon giấc.',
        },
      ];
    }
  }

  Widget _buildGoalChip(String id, String label) {
    final isSelected = _selectedGoal == id;
    return GestureDetector(
      onTap: () => _updateGoal(id),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: isSelected
              ? AppTheme.neonGreen.withValues(alpha: 0.15)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              color: isSelected ? AppTheme.neonGreen : Colors.white60,
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading || _savedSchedule.isEmpty) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(color: AppTheme.neonGreen),
        ),
      );
    }

    final double bmr = _height > 0
        ? (_gender.toLowerCase() == 'female'
              ? (10 * _weight) + (6.25 * _height) - (5 * _age) - 161
              : (10 * _weight) + (6.25 * _height) - (5 * _age) + 5)
        : 0.0;
    final double tdee = bmr * 1.375;
    double targetWorkoutCalories = 0.0;
    if (_selectedGoal == 'lose') {
      targetWorkoutCalories = tdee * 0.10;
    } else if (_selectedGoal == 'build') {
      targetWorkoutCalories = tdee * 0.08;
    } else {
      targetWorkoutCalories = tdee * 0.06;
    }
    if (targetWorkoutCalories < 80) targetWorkoutCalories = 80;
    if (targetWorkoutCalories > 350) targetWorkoutCalories = 350;

    double bmi = _height > 0
        ? _weight / ((_height / 100) * (_height / 100))
        : 0.0;

    String bmiStatus = 'Bình thường';
    Color bmiColor = AppTheme.neonGreen;
    String coachAdvice = '';

    if (bmi < 18.5) {
      bmiStatus = 'Thiếu cân';
      bmiColor = AppTheme.neonBlue;
      coachAdvice =
          'Chỉ số cơ thể cho thấy bạn đang thiếu cân nhẹ. HLV AI khuyên bạn nên tập trung tối đa vào mục tiêu Tăng cơ (Build Muscle) để tăng khối lượng cơ bắp nạc. Hãy ăn nhiều đạm và hạn chế các bài nhảy mất nhiều sức.';
    } else if (bmi < 25.0) {
      bmiStatus = 'Cân đối';
      bmiColor = AppTheme.neonGreen;
      coachAdvice =
          'Thể chất của bạn đang ở trạng thái vô cùng cân đối và lý tưởng! Bạn có thể chọn bất kỳ mục tiêu nào để giữ dáng săn chắc hoặc tăng thêm cơ bắp vai ngực đùi.';
    } else if (bmi < 30.0) {
      bmiStatus = 'Thừa cân';
      bmiColor = Colors.orange;
      coachAdvice =
          'Chỉ số BMI cho thấy bạn đang ở mức thừa cân. AI khuyên bạn nên tập chế độ Giảm cân (Lose Weight). HLV đã tự động loại bỏ bài Burpee khỏi giáo án của bạn để bảo vệ khớp gối chịu áp lực cân nặng.';
    } else {
      bmiStatus = 'Béo phì';
      bmiColor = AppTheme.errorRed;
      coachAdvice =
          'Thể chất của bạn đang thừa mỡ ở mức béo phì. HLV AI đã thiết lập các bài tập an toàn tuyệt đối cho khớp như Plank và Squat có kiểm soát, tránh hoàn toàn các bài nhảy bật mạnh để bảo vệ lưng gối.';
    }

    final isLoseWeight = _selectedGoal == 'lose';

    final int todayIndex = DateTime.now().weekday - 1;
    final int safeTodayIndex = 7 + todayIndex;
    final selectedDayIndex = _selectedDayIndex.clamp(
      0,
      _savedSchedule.length - 1,
    );
    final selectedDayData = _savedSchedule[selectedDayIndex];
    final selectedDayDate = _getSelectedDayDate(selectedDayIndex);

    // Lọc tìm các bài tập hoạt động cho ngày được chọn để chia Calo thích ứng
    final List<dynamic> rawDayExercises = selectedDayData['exercises'] as List<dynamic>? ?? [];
    final double dayBmi = _height > 0 ? _weight / ((_height / 100) * (_height / 100)) : 0.0;
    final List<dynamic> dayActiveExercises = rawDayExercises.where((e) {
      final type = e['type'] as ExerciseType;
      return !_isExerciseBlocked(type, dayBmi, _age);
    }).toList();

    final int dayActiveCount = dayActiveExercises.isEmpty ? 4 : dayActiveExercises.length;
    final double caloriesPerExercise = targetWorkoutCalories / dayActiveCount;

    final scientificTargets = _calculateScientificReps(
      _weight,
      _height,
      _age,
      _selectedGoal,
      _gender,
      activeCount: dayActiveCount,
    );

    return Scaffold(
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverAppBar(
              backgroundColor: Colors.transparent,
              elevation: 0,
              pinned: true,
              leading: IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.white),
                onPressed: () => Navigator.pop(context),
              ),
              title: const Text(
                'AI HLV CÁ NHÂN',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                  letterSpacing: 1.0,
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20.0,
                  vertical: 10.0,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: AppTheme.glassDecoration(
                        color: AppTheme.cardBackground.withValues(alpha: 0.5),
                        borderRadius: 20,
                      ),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Hồ sơ thể chất: $_userName',
                                    style: const TextStyle(
                                      color: Colors.grey,
                                      fontSize: 12,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '${_height.toStringAsFixed(0)} cm/ ${_weight.toStringAsFixed(0)} kg/ $_age tuổi',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                              ElevatedButton.icon(
                                onPressed: _showEditStatsDialog,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.white10,
                                  elevation: 0,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 8,
                                  ),
                                ),
                                icon: const Icon(
                                  Icons.edit,
                                  color: Colors.white,
                                  size: 14,
                                ),
                                label: const Text(
                                  'Sửa',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const Divider(color: Colors.white12, height: 24),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                'Chỉ số BMI hiện tại:',
                                style: TextStyle(
                                  color: Colors.grey,
                                  fontSize: 13,
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: bmiColor.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: bmiColor.withValues(alpha: 0.4),
                                  ),
                                ),
                                child: Text(
                                  '${bmi.toStringAsFixed(1)} - $bmiStatus',
                                  style: TextStyle(
                                    color: bmiColor,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const Divider(color: Colors.white12, height: 24),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'BMR (Trao đổi chất cơ bản):',
                                    style: TextStyle(
                                      color: Colors.grey,
                                      fontSize: 12,
                                    ),
                                  ),
                                  SizedBox(height: 4),
                                  Text(
                                    'TDEE (Tiêu hao năng lượng ngày):',
                                    style: TextStyle(
                                      color: Colors.grey,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    '${bmr.toStringAsFixed(0)} kcal',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '${tdee.toStringAsFixed(0)} kcal',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          const Divider(color: Colors.white12, height: 24),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                'Mục tiêu calo qua bài tập:',
                                style: TextStyle(
                                  color: Colors.grey,
                                  fontSize: 12,
                                ),
                              ),
                              Text(
                                '~${targetWorkoutCalories.toStringAsFixed(0)} kcal/ngày',
                                style: const TextStyle(
                                  color: AppTheme.neonGreen,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                          if (_tooHeavyExercises.isNotEmpty) ...[
                            const Divider(color: Colors.white12, height: 24),
                            SizedBox(
                              width: double.infinity,
                              child: TextButton.icon(
                                onPressed: _resetTooHeavyExercises,
                                style: TextButton.styleFrom(
                                  backgroundColor: Colors.orangeAccent.withValues(alpha: 0.1),
                                  foregroundColor: Colors.orangeAccent,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                    side: const BorderSide(color: Colors.orangeAccent, width: 1),
                                  ),
                                  padding: const EdgeInsets.symmetric(vertical: 10),
                                ),
                                icon: const Icon(Icons.refresh_rounded, size: 16),
                                label: Text(
                                  'Đặt lại bài tập quá sức (${_tooHeavyExercises.length} bài)',
                                  style: const TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: AppTheme.glassDecoration(
                        color: AppTheme.neonGreen.withValues(alpha: 0.08),
                        borderRadius: 16,
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(
                            Icons.support_agent,
                            color: AppTheme.neonGreen,
                            size: 28,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Lời khuyên của HLV AI:',
                                  style: TextStyle(
                                    color: AppTheme.neonGreen,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  coachAdvice,
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.85),
                                    fontSize: 11.5,
                                    height: 1.4,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    const Text(
                      'CHỌN MỤC TIÊU TẬP LUYỆN',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.neonGreen,
                        letterSpacing: 1.5,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E293B),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.08),
                        ),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: _buildGoalChip('lose', '🎯 Giảm cân'),
                          ),
                          Expanded(
                            child: _buildGoalChip('maintain', '⚖️ Giữ dáng'),
                          ),
                          Expanded(
                            child: _buildGoalChip('build', '💪 Tăng cơ'),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        const Icon(
                          Icons.calendar_month,
                          color: AppTheme.neonGreen,
                          size: 18,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            isLoseWeight
                                ? 'LỊCH TRÌNH GIẢM CÂN THEO NGÀY'
                                : 'LỊCH TRÌNH TẬP LUYỆN & DINH DƯỠNG',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.neonGreen,
                              letterSpacing: 1.2,
                            ),
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(3, (weekIdx) {
                        final labels = ['Tuần trước', 'Tuần này', 'Tuần sau'];
                        final isSelected = _selectedWeekIndex == weekIdx;
                        return Expanded(
                          child: GestureDetector(
                            onTap: () {
                              setState(() {
                                _selectedWeekIndex = weekIdx;
                                _selectedDayIndex = weekIdx * 7;
                              });
                              final selectedDate = _getSelectedDayDate(
                                _selectedDayIndex,
                              );
                              _loadCompletedExercisesForDay(selectedDate);
                              _loadMealLogsForDay(selectedDate);
                            },
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              margin: const EdgeInsets.symmetric(horizontal: 4),
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? AppTheme.neonGreen.withValues(alpha: 0.15)
                                    : Colors.white.withValues(alpha: 0.02),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: isSelected
                                      ? AppTheme.neonGreen.withValues(
                                          alpha: 0.4,
                                        )
                                      : Colors.white.withValues(alpha: 0.05),
                                  width: 1,
                                ),
                              ),
                              child: Center(
                                child: Text(
                                  labels[weekIdx],
                                  style: TextStyle(
                                    color: isSelected
                                        ? AppTheme.neonGreen
                                        : Colors.white60,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        );
                      }),
                    ),
                    const SizedBox(height: 12),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final shortWeekdays = [
                          'T2',
                          'T3',
                          'T4',
                          'T5',
                          'T6',
                          'T7',
                          'CN',
                        ];
                        final cellWidth = (constraints.maxWidth - (6 * 6)) / 7;
                        return Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: List.generate(7, (colIndex) {
                            final dayGlobalIndex =
                                (_selectedWeekIndex * 7) + colIndex;
                            final isToday = dayGlobalIndex == safeTodayIndex;
                            final isSelected =
                                dayGlobalIndex == selectedDayIndex;
                            final isCompleted = _isDayWorkoutCompleted(
                              dayGlobalIndex,
                              _savedSchedule,
                            );
                            final dayDate = _getSelectedDayDate(dayGlobalIndex);

                            return GestureDetector(
                              onTap: () {
                                setState(() {
                                  _selectedDayIndex = dayGlobalIndex;
                                });
                                final selectedDate = _getSelectedDayDate(
                                  dayGlobalIndex,
                                );
                                _loadCompletedExercisesForDay(selectedDate);
                                _loadMealLogsForDay(selectedDate);
                              },
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 200),
                                width: cellWidth,
                                height: 70,
                                decoration: isSelected
                                    ? BoxDecoration(
                                        gradient: const LinearGradient(
                                          colors: [
                                            Color(0xFF3B82F6),
                                            Color(0xFF1D4ED8),
                                          ],
                                          begin: Alignment.topCenter,
                                          end: Alignment.bottomCenter,
                                        ),
                                        borderRadius: BorderRadius.circular(12),
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.blue.withValues(
                                              alpha: 0.25,
                                            ),
                                            blurRadius: 6,
                                            offset: const Offset(0, 2),
                                          ),
                                        ],
                                      )
                                    : BoxDecoration(
                                        color: isToday
                                            ? Colors.white.withValues(
                                                alpha: 0.08,
                                              )
                                            : Colors.white.withValues(
                                                alpha: 0.02,
                                              ),
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(
                                          color: isToday
                                              ? AppTheme.neonGreen.withValues(
                                                  alpha: 0.3,
                                                )
                                              : Colors.white.withValues(
                                                  alpha: 0.05,
                                                ),
                                          width: 1,
                                        ),
                                      ),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(
                                      shortWeekdays[colIndex],
                                      style: TextStyle(
                                        color: isSelected
                                            ? Colors.white
                                            : (isToday
                                                  ? AppTheme.neonGreen
                                                  : Colors.white.withValues(
                                                      alpha: 0.5,
                                                    )),
                                        fontWeight: FontWeight.bold,
                                        fontSize: 10,
                                      ),
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      '${dayDate.day}',
                                      style: TextStyle(
                                        color: isSelected
                                            ? Colors.white
                                            : (isToday
                                                  ? AppTheme.neonGreen
                                                  : Colors.white),
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Container(
                                      width: 5,
                                      height: 5,
                                      decoration: BoxDecoration(
                                        color: isCompleted
                                            ? AppTheme.neonGreen
                                            : (isSelected
                                                  ? Colors.white54
                                                  : Colors.transparent),
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }),
                        );
                      },
                    ),
                    const SizedBox(height: 20),
                    NutritionPanel(
                      weight: _weight,
                      height: _height,
                      age: _age,
                      selectedGoal: _selectedGoal,
                      bmi: bmi,
                      selectedDayDate: selectedDayDate,
                      todayMealLogs: _todayMealLogs,
                      gender: _gender,
                      onMealLogsUpdated: (updatedLogs) {
                        setState(() {
                          _todayMealLogs = updatedLogs;
                        });
                        _saveMealLogsForDay(selectedDayDate);
                      },
                    ),
                    const SizedBox(height: 8),
                    Container(
                      margin: const EdgeInsets.only(bottom: 20),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E293B),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.white10),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: Theme(
                          data: Theme.of(
                            context,
                          ).copyWith(dividerColor: Colors.transparent),
                          child: ExpansionTile(
                            key: const PageStorageKey<String>('workout_panel'),
                            initiallyExpanded: true,
                            title: Row(
                              children: [
                                const Icon(
                                  Icons.fitness_center,
                                  color: AppTheme.neonGreen,
                                  size: 20,
                                ),
                                const SizedBox(width: 8),
                                const Expanded(
                                  child: Text(
                                    '💪 LUYỆN TẬP & BÀI TẬP ĐỀ XUẤT',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: AppTheme.neonGreen,
                                      letterSpacing: 0.8,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            subtitle: Builder(
                              builder: (context) {
                                final List<dynamic> currentExercises =
                                    selectedDayData['exercises']
                                        as List<dynamic>? ??
                                    [];
                                final bool isRest =
                                    selectedDayData['isRest'] as bool? ?? false;

                                if (isRest) {
                                  return const Text(
                                    'Hôm nay: Nghỉ ngơi & phục hồi',
                                    style: TextStyle(
                                      color: Colors.white70,
                                      fontSize: 11,
                                    ),
                                  );
                                }

                                int totalExercises = currentExercises.length;
                                int completedCount = 0;
                                for (var rec in currentExercises) {
                                  final ExerciseType type =
                                      rec['type'] as ExerciseType;
                                  if (_isExerciseCompletedForDay(
                                    type,
                                    selectedDayDate,
                                  )) {
                                    completedCount++;
                                  }
                                }
                                return Text(
                                  'Đã tập: $completedCount / $totalExercises bài (${totalExercises > 0 ? ((completedCount / totalExercises) * 100).toStringAsFixed(0) : 0}%)',
                                  style: TextStyle(
                                    color:
                                        completedCount == totalExercises &&
                                            totalExercises > 0
                                        ? AppTheme.neonGreen
                                        : Colors.white70,
                                    fontSize: 11,
                                    fontWeight:
                                        completedCount == totalExercises &&
                                            totalExercises > 0
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                                  ),
                                );
                              },
                            ),
                            childrenPadding: const EdgeInsets.all(16),
                            expandedCrossAxisAlignment:
                                CrossAxisAlignment.start,
                            children: [
                              if (selectedDayData['title'] != null) ...[
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 8,
                                  ),
                                  margin: const EdgeInsets.only(bottom: 12),
                                  decoration: BoxDecoration(
                                    color: Colors.black12,
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(color: Colors.white10),
                                  ),
                                  child: Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      const Text(
                                        'TIÊU ĐIỂM HÔM NAY:',
                                        style: TextStyle(
                                          color: Colors.grey,
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          selectedDayData['title']
                                              .toString()
                                              .toUpperCase(),
                                          style: const TextStyle(
                                            color: AppTheme.neonGreen,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 12,
                                          ),
                                          textAlign: TextAlign.end,
                                          overflow: TextOverflow.ellipsis,
                                          maxLines: 1,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                              Builder(
                                builder: (context) {
                                  final bool isRest =
                                      selectedDayData['isRest'] as bool? ??
                                      false;
                                  final bool isToday =
                                      selectedDayIndex == safeTodayIndex;

                                  if (isRest) {
                                    return Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Container(
                                          width: double.infinity,
                                          padding: const EdgeInsets.all(16),
                                          decoration: BoxDecoration(
                                            color: Colors.black12,
                                            borderRadius: BorderRadius.circular(
                                              12,
                                            ),
                                            border: Border.all(
                                              color: Colors.white10,
                                            ),
                                          ),
                                          child: Column(
                                            children: [
                                              const Icon(
                                                Icons.spa,
                                                color: AppTheme.neonBlue,
                                                size: 36,
                                              ),
                                              const SizedBox(height: 8),
                                              const Text(
                                                'NGÀY NGHỈ NGƠI & PHỤC HỒI',
                                                style: TextStyle(
                                                  color: AppTheme.neonBlue,
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 13,
                                                ),
                                              ),
                                              const SizedBox(height: 6),
                                              Text(
                                                selectedDayData['reason']
                                                    .toString(),
                                                textAlign: TextAlign.center,
                                                style: const TextStyle(
                                                  color: Colors.white70,
                                                  fontSize: 11,
                                                  height: 1.4,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(height: 12),
                                        if (isToday&&!isRest) ...[
                                          _buildExerciseGroupSelector(
                                            bmi,
                                            _age,
                                            selectedDayDate,
                                          ),
                                          if (_isCustomSelectionActive &&
                                              _customSelectedExercises
                                                  .isNotEmpty) ...[
                                            const SizedBox(height: 12),
                                            const Divider(
                                              color: Colors.white10,
                                              height: 20,
                                            ),
                                            ..._buildCustomExerciseList(
                                              scientificTargets,
                                            ).map((rec) {
                                              return _buildExerciseCard(
                                                rec,
                                                scientificTargets,
                                                caloriesPerExercise,
                                                true,
                                                selectedDayDate,
                                                bmi,
                                                _age,
                                              );
                                            }),
                                          ],
                                        ],
                                      ],
                                    );
                                  }

                                  List<dynamic> currentExercises =
                                      selectedDayData['exercises']
                                          as List<dynamic>? ??
                                      [];

                                  // Lọc bài tập: Loại bỏ các bài tập bị quá sức hoặc bị chặn
                                  List<dynamic> activeExercises = currentExercises.where((e) {
                                    final type = e['type'] as ExerciseType;
                                    return !_isExerciseBlocked(type, bmi, _age);
                                  }).toList();

                                  // Nếu tất cả các bài tập bị chặn hết, cung cấp một bài tập thay thế nhẹ nhàng
                                  if (activeExercises.isEmpty && currentExercises.isNotEmpty) {
                                    ExerciseType fallback = ExerciseType.plank;
                                    if (_isExerciseBlocked(fallback, bmi, _age)) {
                                      fallback = ExerciseType.squat;
                                    }
                                    if (_isExerciseBlocked(fallback, bmi, _age)) {
                                      fallback = ExerciseType.jumping_jack;
                                    }
                                    activeExercises = [
                                      {
                                        'type': fallback,
                                        'reason': 'Bài tập nhẹ nhàng thay thế (các bài tập khác quá sức hoặc bị chặn)'
                                      }
                                    ];
                                  }

                                  if (currentExercises.isEmpty) {
                                    if (isToday && !isRest) {
                                      return Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          _buildModeSelector(),
                                          if (_isCustomSelectionActive) ...[
                                            _buildExerciseGroupSelector(
                                              bmi,
                                              _age,
                                              selectedDayDate,
                                            ),
                                          ],
                                        ],
                                      );
                                    }
                                    return const SizedBox.shrink();
                                  }

                                  int totalExercises = activeExercises.length;
                                  int completedCount = 0;
                                  final List<String> completedList = [];
                                  final List<String> missingList = [];

                                  for (var rec in activeExercises) {
                                    final ExerciseType type =
                                        rec['type'] as ExerciseType;
                                    final originalExercise = ExerciseDetail
                                        .defaultExercises
                                        .firstWhere((e) => e.type == type);
                                    final bool isCompleted =
                                        _isExerciseCompletedForDay(
                                          type,
                                          selectedDayDate,
                                        );
                                    if (isCompleted) {
                                      completedCount++;
                                      completedList.add(originalExercise.name);
                                    } else {
                                      missingList.add(originalExercise.name);
                                    }
                                  }

                                  return Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      if (isToday && !isRest) ...[
                                        _buildModeSelector(),
                                        if (_isCustomSelectionActive) ...[
                                          _buildExerciseGroupSelector(
                                            bmi,
                                            _age,
                                            selectedDayDate,
                                          ),
                                          const SizedBox(height: 12),
                                          const Divider(
                                            color: Colors.white10,
                                            height: 1,
                                          ),
                                          const SizedBox(height: 12),
                                        ],
                                        if (!_isCustomSelectionActive)
                                          Padding(
                                            padding: const EdgeInsets.only(
                                              bottom: 10,
                                            ),
                                            child: Row(
                                              children: [
                                                Icon(
                                                  Icons.auto_awesome,
                                                  size: 13,
                                                  color: AppTheme.neonGreen
                                                      .withValues(alpha: 0.8),
                                                ),
                                                const SizedBox(width: 5),
                                                Text(
                                                  'GIÁO ÁN AI GỢI Ý (mặc định)',
                                                  style: TextStyle(
                                                    color: AppTheme.neonGreen
                                                        .withValues(alpha: 0.8),
                                                    fontSize: 10,
                                                    fontWeight: FontWeight.bold,
                                                    letterSpacing: 0.8,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                      ],
                                      Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,
                                        children: [
                                          const Text(
                                            'TIẾN ĐỘ THỰC HIỆN',
                                            style: TextStyle(
                                              color: Colors.white70,
                                              fontSize: 10,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                          Text(
                                            '$completedCount/$totalExercises bài',
                                            style: const TextStyle(
                                              color: AppTheme.neonGreen,
                                              fontSize: 11,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 6),
                                      ClipRRect(
                                        borderRadius: BorderRadius.circular(4),
                                        child: LinearProgressIndicator(
                                          value: (totalExercises > 0)
                                              ? (completedCount /
                                                    totalExercises)
                                              : 0,
                                          backgroundColor: Colors.white10,
                                          valueColor:
                                              const AlwaysStoppedAnimation<
                                                Color
                                              >(AppTheme.neonGreen),
                                          minHeight: 6,
                                        ),
                                      ),
                                      const SizedBox(height: 12),
                                      Container(
                                        width: double.infinity,
                                        padding: const EdgeInsets.all(10),
                                        decoration: BoxDecoration(
                                          color:
                                              completedCount == totalExercises
                                              ? AppTheme.neonGreen.withValues(
                                                  alpha: 0.05,
                                                )
                                              : AppTheme.errorRed.withValues(
                                                  alpha: 0.05,
                                                ),
                                          borderRadius: BorderRadius.circular(
                                            10,
                                          ),
                                          border: Border.all(
                                            color:
                                                completedCount == totalExercises
                                                ? AppTheme.neonGreen.withValues(
                                                    alpha: 0.15,
                                                  )
                                                : AppTheme.errorRed.withValues(
                                                    alpha: 0.15,
                                                  ),
                                          ),
                                        ),
                                        child: Row(
                                          children: [
                                            Icon(
                                              completedCount == totalExercises
                                                  ? Icons.stars_rounded
                                                  : Icons.warning_amber_rounded,
                                              color:
                                                  completedCount ==
                                                      totalExercises
                                                  ? AppTheme.neonGreen
                                                  : AppTheme.errorRed,
                                              size: 16,
                                            ),
                                            const SizedBox(width: 8),
                                            Expanded(
                                              child: Text(
                                                completedCount == totalExercises
                                                    ? 'Tuyệt vời! Bạn đã hoàn thành toàn bộ bài tập của ngày này!'
                                                    : 'Bạn đang thiếu bài tập: ${missingList.join(", ")}.',
                                                style: TextStyle(
                                                  color:
                                                      completedCount ==
                                                          totalExercises
                                                      ? AppTheme.neonGreen
                                                      : AppTheme.errorRed,
                                                  fontSize: 10.5,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const Divider(
                                        color: Colors.white10,
                                        height: 24,
                                      ),
                                      ...activeExercises.map((rec) {
                                        return _buildExerciseCard(
                                          rec as Map<String, dynamic>,
                                          scientificTargets,
                                          caloriesPerExercise,
                                          selectedDayIndex == safeTodayIndex,
                                          selectedDayDate,
                                          bmi,
                                          _age,
                                        );
                                      }),
                                    ],
                                  );
                                },
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildExerciseCard(
    Map<String, dynamic> rec,
    Map<ExerciseType, int> scientificTargets,
    double caloriesPerExercise,
    bool allowWorkoutAction,
    DateTime selectedDayDate,
    double bmi,
    int age,
  ) {
    final ExerciseType type = rec['type'] as ExerciseType;
    final String reason = rec['reason'] as String;

    final int recommendedTarget =
        scientificTargets[type] ?? (rec['target'] as int? ?? 0);
    final int currentTarget = _selectedTargets[type] ?? recommendedTarget;
    final List<int> availableTargets = {
      recommendedTarget,
      if (rec['customTargets'] != null) ...List<int>.from(rec['customTargets']),
      if (ExerciseDetail.defaultExercises.any((e) => e.type == type))
        ...((ExerciseDetail.defaultExercises
                .firstWhere((e) => e.type == type)
                .isDurationBased)
            ? [60, 90, 120, 240, 300, 360]
            : ExerciseDetail.targetOptions),
    }.toList()..sort();

    final bool isNoSplit = _noSplitTargets[type] ?? false;
    final bool isTargetSelectorExpanded =
        _expandedTargetSelectors[type] ?? false;
    final bool isCompletedForDay = _isExerciseCompletedForDay(
      type,
      selectedDayDate,
    );
    final bool isBlocked = _isExerciseBlocked(type, bmi, age);
    final bool isRepeated = _isExerciseDoneOnDate(
      type,
      selectedDayDate.subtract(const Duration(days: 1)),
    );
    final originalExercise = ExerciseDetail.defaultExercises.firstWhere(
      (e) => e.type == type,
    );

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration:
          AppTheme.glassDecoration(
            color: isBlocked
                ? AppTheme.errorRed.withValues(alpha: 0.1)
                : AppTheme.cardBackground.withValues(alpha: 0.3),
            borderRadius: 20,
          ).copyWith(
            border: Border.all(
              color: isBlocked
                  ? AppTheme.errorRed.withValues(alpha: 0.35)
                  : Colors.white10,
              width: 1,
            ),
          ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.05),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  originalExercise.icon,
                  color: AppTheme.neonGreen,
                  size: 22,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      originalExercise.name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'Đề xuất AI: $recommendedTarget ${originalExercise.isDurationBased ? "giây giữ" : "lần tập"}',
                      style: const TextStyle(
                        color: AppTheme.neonGreen,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (allowWorkoutAction) ...[
            GestureDetector(
              onTap: () {
                setState(() {
                  _expandedTargetSelectors[type] = !(isTargetSelectorExpanded);
                });
              },
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'CHỌN SỐ LƯỢNG KHÁC:',
                      style: TextStyle(
                        color: AppTheme.neonGreen,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  Icon(
                    isTargetSelectorExpanded
                        ? Icons.keyboard_arrow_up
                        : Icons.keyboard_arrow_down,
                    color: AppTheme.neonGreen,
                    size: 16,
                  ),
                ],
              ),
            ),
            if (isTargetSelectorExpanded) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: availableTargets.map((option) {
                  final isSelected = currentTarget == option;
                  return ChoiceChip(
                    label: Text(
                      originalExercise.isDurationBased
                          ? '$option giây'
                          : '$option lần',
                    ),
                    selected: isSelected,
                    selectedColor: AppTheme.neonGreen,
                    backgroundColor: Colors.white.withValues(alpha: 0.05),
                    labelStyle: TextStyle(
                      color: isSelected ? Colors.black : Colors.white70,
                      fontWeight: FontWeight.bold,
                      fontSize: 11.5,
                    ),
                    onSelected: (_) {
                      setState(() {
                        _selectedTargets[type] = option;
                      });
                    },
                  );
                }).toList(),
              ),
              const SizedBox(height: 10),
            ],
          ],
          if (isBlocked) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              margin: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(
                color: AppTheme.errorRed.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      _getBlockedReason(type, bmi, age),
                      style: const TextStyle(
                        color: AppTheme.errorRed,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        height: 1.3,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ] else if (isRepeated) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              margin: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Text(
                '⚠️ Bài này đã được tập hôm trước nên đã bị loại khỏi lựa chọn hôm nay.',
                style: TextStyle(
                  color: Colors.orange,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  height: 1.3,
                ),
              ),
            ),
          ],
          Text(
            reason,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.75),
              fontSize: 11.5,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 10),
          if (allowWorkoutAction)
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: const Text(
                'Tập liên tục (không chia hiệp)',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 12.5,
                  fontWeight: FontWeight.bold,
                ),
              ),
              subtitle: const Text(
                'Bỏ qua đếm ngược và chia chặng nghỉ giữa giờ.',
                style: TextStyle(color: Colors.grey, fontSize: 10.5),
              ),
              value: isNoSplit,
              activeThumbColor: AppTheme.neonGreen,
              onChanged: (val) {
                setState(() {
                  _noSplitTargets[type] = val;
                });
              },
            )
          else
            Container(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  Icon(
                    isCompletedForDay
                        ? Icons.check_circle
                        : Icons.radio_button_unchecked,
                    color: isCompletedForDay ? AppTheme.neonGreen : Colors.grey,
                    size: 16,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    isCompletedForDay ? 'Đã hoàn thành' : 'Chưa hoàn thành',
                    style: TextStyle(
                      color: isCompletedForDay
                          ? AppTheme.neonGreen
                          : Colors.white70,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          const Divider(color: Colors.white10, height: 20),
          Row(
            children: [
              Expanded(
                child: allowWorkoutAction
                    ? GestureDetector(
                        onTap: () => _toggleExerciseCompletedForDay(
                          type,
                          selectedDayDate,
                          currentTarget,
                          isManual: true,
                        ),
                        behavior: HitTestBehavior.opaque,
                        child: Row(
                          children: [
                            Icon(
                              isCompletedForDay
                                  ? Icons.check_circle
                                  : Icons.radio_button_unchecked,
                              color: isCompletedForDay
                                  ? AppTheme.neonGreen
                                  : Colors.white60,
                              size: 16,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              isCompletedForDay
                                  ? 'Đã hoàn thành'
                                  : 'Chưa hoàn thành',
                              style: TextStyle(
                                color: isCompletedForDay
                                    ? AppTheme.neonGreen
                                    : Colors.white70,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      )
                    : Text(
                        'Chỉ xem lịch cho ngày này',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.6),
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
              ),
              if (allowWorkoutAction) ...[
                const SizedBox(width: 8),
                Builder(
                  builder: (context) {
                    final isDraftForThisExercise =
                        _todayDraftWorkout != null &&
                        _todayDraftWorkout!['exerciseType'] ==
                            originalExercise.type.name &&
                        ((_todayDraftWorkout!['sourceTag'] as String?) ?? '')
                            .startsWith('recommended:');
                    return ElevatedButton.icon(
                      onPressed: () async {
                        final navigatorContext = context;
                        final finalTargetCount = isDraftForThisExercise
                            ? (_todayDraftWorkout!['targetCount'] as num)
                                  .toInt()
                            : currentTarget;
                        final finalNoSplit = isDraftForThisExercise
                            ? (_todayDraftWorkout!['noSplit'] as bool? ?? false)
                            : isNoSplit;
                        final finalCompletedCount = isDraftForThisExercise
                            ? (_todayDraftWorkout!['completedCount'] as num?)
                                      ?.toInt() ??
                                  0
                            : 0;

                        final result = navigatorContext.mounted
                            ? await Navigator.push(
                                navigatorContext,
                                MaterialPageRoute(
                                  builder: (context) => WorkoutScreen(
                                    exercise: originalExercise,
                                    cameras: widget.cameras,
                                    targetCount: finalTargetCount,
                                    noSplit: finalNoSplit,
                                    sourceTag:
                                        'recommended:${selectedDayDate.toIso8601String()}:${type.name}:$finalTargetCount',
                                    initialCompletedCount: finalCompletedCount,
                                  ),
                                ),
                              )
                            : null;

                        await _refreshTodayDraftWorkout();
                        if ((result == true || result == 'complete') &&
                            mounted) {
                          _toggleExerciseCompletedForDay(
                            type,
                            selectedDayDate,
                            finalTargetCount,
                            isManual: false,
                          );
                          await _loadCompletedExercisesForDay(selectedDayDate);
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.neonGreen,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                      ),
                      icon: const Icon(
                        Icons.play_arrow,
                        color: Colors.black,
                        size: 16,
                      ),
                      label: Text(
                        isDraftForThisExercise ? 'TẬP TIẾP' : 'TẬP NGAY',
                        style: const TextStyle(
                          color: Colors.black,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    );
                  },
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  bool isGoalAllowedForBmi(String goal, double bmi) {
    if (bmi < 18.5) return goal == 'build';
    if (bmi >= 25.0) return goal == 'lose';
    return true;
  }
}
