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
  final WorkoutDraftService _workoutDraftService = WorkoutDraftService();
  Map<String, dynamic>? _todayDraftWorkout;
  double _weight = 0.0;
  double _height = 0.0;
  int _age = 0;
  String _gender = 'male';
  String _userName = '';
  bool _isLoading = true;
  String _selectedGoal = 'maintain'; // 'lose', 'maintain', 'build'
  int _selectedDayIndex = 7; // Chọn ngày trong lịch trình (0 - 20)
  int _selectedWeekIndex = 1; // 0 = Tuần trước, 1 = Tuần này, 2 = Tuần sau
  final Map<ExerciseType, bool> _noSplitTargets = {};
  final Map<ExerciseType, int> _selectedTargets = {};
  final Map<ExerciseType, bool> _expandedTargetSelectors = {};
  final Map<String, Set<String>> _completedExerciseKeysByDay = {};
  List<Map<String, dynamic>> _todayMealLogs = [];
  List<String> _heavyExercises = [];

  @override
  void initState() {
    super.initState();
    _selectedWeekIndex = 1;
    _selectedDayIndex = 7 + (DateTime.now().weekday - 1);
    _loadUserProfile();
    _loadHeavyExercises();

    final selectedDate = _getSelectedDayDate(_selectedDayIndex);
    _loadCompletedExercisesForDay(selectedDate);
    _loadMealLogsForDay(selectedDate);
    _refreshTodayDraftWorkout();
  }

  Future<void> _loadHeavyExercises() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = prefs.getStringList('heavy_exercises') ?? [];
      if (mounted) {
        setState(() {
          _heavyExercises = list;
        });
      }
    } catch (e) {
      debugPrint('Lỗi tải bài tập quá nặng: $e');
    }
  }

  ExerciseType _getAdaptedExerciseType(ExerciseType type) {
    ExerciseType current = type;
    while (_heavyExercises.contains(current.name)) {
      if (current == ExerciseType.burpee) {
        current = ExerciseType.jumpingJack;
      } else if (current == ExerciseType.pushUp) {
        current = ExerciseType.plank;
      } else if (current == ExerciseType.walkingLunge) {
        current = ExerciseType.squat;
      } else if (current == ExerciseType.squat) {
        current = ExerciseType.jumpingJack;
      } else if (current == ExerciseType.jumpingJack) {
        current = ExerciseType.plank;
      } else {
        break; 
      }
    }
    return current;
  }

  String _getAdaptedReason(ExerciseType originalType, ExerciseType adaptedType, String originalReason) {
    if (originalType == adaptedType) return originalReason;
    final adaptedEx = ExerciseDetail.defaultExercises.firstWhere((e) => e.type == adaptedType);
    final originalEx = ExerciseDetail.defaultExercises.firstWhere((e) => e.type == originalType);
    return 'Bài tập thay thế: Bạn tập ${originalEx.name} chưa quen nên HLV tự động chuyển sang ${adaptedEx.name} nhẹ hơn để bảo vệ cơ thể.';
  }

  List<Map<String, dynamic>> _postProcessAdaptiveSchedule(List<Map<String, dynamic>> rawSchedule) {
    // rawSchedule có 7 phần tử (Day 1 -> Day 7). Nhân bản thành 3 tuần (21 phần tử)
    final List<Map<String, dynamic>> raw21 = [];
    
    // Tuần 1: Tuần trước (ngày 1 - 7)
    for (int i = 0; i < 7; i++) {
      final dayCopy = Map<String, dynamic>.from(rawSchedule[i]);
      dayCopy['day'] = i + 1; // 1 đến 7
      dayCopy['weekLabel'] = 'Tuần trước';
      raw21.add(dayCopy);
    }
    
    // Tuần 2: Tuần này (ngày 8 - 14)
    for (int i = 0; i < 7; i++) {
      final dayCopy = Map<String, dynamic>.from(rawSchedule[i]);
      dayCopy['day'] = i + 8; // 8 đến 14
      dayCopy['weekLabel'] = 'Tuần này';
      raw21.add(dayCopy);
    }
    
    // Tuần 3: Tuần sau (ngày 15 - 21)
    for (int i = 0; i < 7; i++) {
      final dayCopy = Map<String, dynamic>.from(rawSchedule[i]);
      dayCopy['day'] = i + 15; // 15 đến 21
      dayCopy['weekLabel'] = 'Tuần sau';
      raw21.add(dayCopy);
    }

    final List<Map<String, dynamic>> processed = [];
    for (final day in raw21) {
      final dayCopy = Map<String, dynamic>.from(day);
      if (dayCopy['isRest'] == true) {
        processed.add(dayCopy);
        continue;
      }
      final List<dynamic> exercises = List.from(dayCopy['exercises'] as List);
      final List<Map<String, dynamic>> newExercises = [];
      for (int i = 0; i < exercises.length; i++) {
        final exMap = Map<String, dynamic>.from(exercises[i] as Map);
        final ExerciseType originalType = exMap['type'] as ExerciseType;
        final ExerciseType adaptedType = _getAdaptedExerciseType(originalType);
        
        if (originalType != adaptedType) {
          exMap['type'] = adaptedType;
          exMap['reason'] = _getAdaptedReason(originalType, adaptedType, exMap['reason'] as String);
        }
        newExercises.add(exMap);
      }
      dayCopy['exercises'] = newExercises;
      processed.add(dayCopy);
    }
    return processed;
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

          // Đọc mục tiêu tập luyện từ database nếu có lưu trước đó
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

          // Đồng bộ ngược lại database nếu mục tiêu bị cưỡng chế thay đổi do BMI
          if (_selectedGoal != dbGoal) {
            _updateGoal(_selectedGoal);
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
        await _updateGoal(nextGoal);
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

  // Cập nhật mục tiêu và đồng bộ lên Database
  Future<void> _updateGoal(String newGoal) async {
    setState(() {
      _selectedGoal = newGoal;
    });

    if (!_isSupabaseInitialized) return;

    try {
      final client = Supabase.instance.client;
      final userId = client.auth.currentUser?.id;
      if (userId != null) {
        try {
          await client
              .from('ho_so_nguoi_dung')
              .update({'muc_tieu': newGoal})
              .eq('ma_nguoi_dung', userId);
        } catch (dbError) {
          debugPrint(
            'Lỗi cập nhật mục tiêu CSDL: $dbError',
          );
        }
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
    final todayIndex = now.weekday - 1; // 0 = Monday, 6 = Sunday
    final startOfToday = DateTime(now.year, now.month, now.day);
    final mondayOfThisWeek = startOfToday.subtract(Duration(days: todayIndex));
    return mondayOfThisWeek.add(Duration(days: index - 7));
  }

  bool _isDayWorkoutCompleted(
    int index,
    List<Map<String, dynamic>> adaptiveSchedule,
  ) {
    final dayDate = _getSelectedDayDate(index);
    final selectedDayData = adaptiveSchedule[index];
    final List<dynamic> currentExercises =
        selectedDayData['exercises'] as List<dynamic>? ?? [];
    final bool isRest = selectedDayData['isRest'] as bool? ?? false;

    if (isRest) return true; // Ngày nghỉ xem như đã xong
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

    return completionKeys.any((key) {
      final parts = key.split('::');
      if (parts.length < 3) return false;

      final keyType = _exerciseTypeFromName(parts[0]);

      final isRecommended = parts[2].toLowerCase() == 'recommended';

      return isRecommended && keyType == type;
    });
  }

  String _buildCompletionKey({
    required ExerciseType type,
    required int repsCount,
    required bool isRecommended,
  }) {
    return '${type.name}::$repsCount::${isRecommended ? 'recommended' : 'custom'}';
  }

  String? _parseCompletionKeyFromRecord(String exerciseId, int repsCount) {
    final parts = exerciseId.split('::');
    if (parts.length < 3) return null;

    final exerciseType = _exerciseTypeFromName(parts.first);
    if (exerciseType == null) return null;

    final parsedRepsCount = int.tryParse(parts[1]) ?? 0;
    final isRecommended = parts[2].toLowerCase() == 'recommended';

    if (!isRecommended) return null;

    return _buildCompletionKey(
      type: exerciseType,
      repsCount: parsedRepsCount > 0 ? parsedRepsCount : repsCount,
      isRecommended: true,
    );
  }

  Future<void> _loadCompletedExercisesForDay(DateTime day) async {
    if (!_isSupabaseInitialized) return;

    try {
      final completedRecords = await DatabaseService()
          .getCompletedExerciseRecordsForDate(day);
      final dayKey = _getDayKey(day);

      final parsedKeys = completedRecords
          .map<String?>((row) {
            final exerciseId = (row['exercise_id'] as String?) ?? '';
            final repsCount = (row['reps_count'] as num?)?.toInt() ?? 0;
            return _parseCompletionKeyFromRecord(exerciseId, repsCount);
          })
          .whereType<String>()
          .toSet();

      if (mounted) {
        setState(() {
          _completedExerciseKeysByDay[dayKey] = parsedKeys;
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

    final completionKey = _buildCompletionKey(
      type: type,
      repsCount: targetCount,
      isRecommended: true,
    );

    if (completedForDay.contains(completionKey)) {
      completedForDay.remove(completionKey);
    } else {
      completedForDay.add(completionKey);

      if (isManual) {
        try {
          await DatabaseService().saveWorkoutResult(
            exerciseType: type.name,
            repsCount: targetCount,
            durationSeconds:
                type == ExerciseType.plank || type == ExerciseType.jumpingJack
                ? targetCount
                : 45,
            caloriesBurned: type == ExerciseType.plank
                ? targetCount * 0.1
                : targetCount * 0.4,
            incorrectPostures: 0,
            sourceTag:
                'recommended:${day.toIso8601String()}:${type.name}:$targetCount',
          );
        } catch (e) {
          debugPrint('Lỗi đồng bộ tick bài tập: $e');
        }
      }
    }

    if (mounted) {
      setState(() {});
    }
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
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
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
                      child: Text('Nam (Male)', style: TextStyle(color: Colors.white)),
                    ),
                    DropdownMenuItem(
                      value: 'female',
                      child: Text('Nữ (Female)', style: TextStyle(color: Colors.white)),
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

  // Thuật toán tính mục tiêu reps/seconds dựa trên TDEE & Mifflin-St Jeor theo chuẩn khoa học thể thao
  Map<ExerciseType, int> _calculateScientificReps(
    double weight,
    double height,
    int age,
    String goal,
    String gender,
  ) {
    // 1. Tính toán các chỉ số nền tảng
    double bmi = weight / ((height / 100) * (height / 100));

    double bmr = 0.0;
    if (gender.toLowerCase() == 'female') {
      bmr = (10 * weight) + (6.25 * height) - (5 * age) - 161;
    } else {
      bmr = (10 * weight) + (6.25 * height) - (5 * age) + 5;
    }
    if (bmr < 1000) bmr = 1000;

    // 2. Tự động điều chỉnh hệ số hoạt động dựa trên thể trạng
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

    // 3. Tùy chỉnh mục tiêu Calo nạp vào dựa trên phân loại BMI của bạn
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

    // 4. Tính toán calo cho buổi tập (Workout Calories)
    double targetWorkoutCalories = 0.0;
    if (bmi >= 25.0 || goal == 'lose') {
      targetWorkoutCalories = tdee * 0.12;
    } else if (goal == 'build') {
      targetWorkoutCalories = tdee * 0.08;
    } else {
      targetWorkoutCalories = tdee * 0.06;
    }

    targetWorkoutCalories = targetWorkoutCalories.clamp(80, 350);

    // Chia đều cho 4 bài tập
    final double caloriesPerExercise = targetWorkoutCalories / 4;
    final Map<ExerciseType, int> computedTargets = {};

    // Tỉ lệ cân nặng để cá nhân hóa lượng calo tiêu thụ
    double weightFactor = weight / 70.0;

    for (final exercise in ExerciseDetail.defaultExercises) {
      if (exercise.isDurationBased) {
        // --- BÀI TẬP TÍNH THEO GIÂY (Plank, Jumping Jacks...) ---
        // Giả sử cpm là calo tiêu thụ mỗi phút của người 70kg
        double personalizedCpm = exercise.caloriesPerMin * weightFactor;
        double sec =
            (caloriesPerExercise * 60) /
            (personalizedCpm > 0 ? personalizedCpm : 1); // Tránh chia cho 0

        // Làm tròn đến hàng chục và nới rộng clamp (30s - 240s) để thấy sự khác biệt thể trạng
        int roundedSec = ((sec / 10).round() * 10).clamp(30, 240);
        if (bmi >= 25.0) {
          roundedSec = roundedSec.clamp(30, 120);
        }
        if (gender.toLowerCase() == 'female') {
          roundedSec = (roundedSec * 0.85).round();
        }
        computedTargets[exercise.type] = roundedSec;
      } else {
        // --- BÀI TẬP TÍNH THEO REP (Push-up, Squat, Burpee...) ---
        // Lấy chỉ số calo thực tế trên 1 rep của từng bài (Dựa trên người 70kg)
        double caloriesPerRep = _getCaloPerRep(exercise.type) * weightFactor;

        double reps =
            caloriesPerExercise /
            (caloriesPerRep > 0 ? caloriesPerRep : 1); // Tránh chia cho 0
        // Làm tròn đến số chia hết cho 2 hoặc 5 (ở đây giữ nguyên chia hết cho 5 của bạn)
        int roundedReps = ((reps / 5).round() * 5);
        if (gender.toLowerCase() == 'female') {
          roundedReps = (roundedReps * 0.85).round();
        }

        // Nới rộng khoảng clamp để phân biệt rõ người khỏe/yếu, nặng/nhẹ cân
        // giới hạn theo ACSM khuyến nghị hoa kì
        if (bmi >= 25.0) {
          if (exercise.type == ExerciseType.burpee) {
            roundedReps = roundedReps.clamp(5, 30);
          } else if (exercise.type == ExerciseType.pushUp) {
            roundedReps = roundedReps.clamp(5, 40);
          } else if (exercise.type == ExerciseType.squat) {
            roundedReps = roundedReps.clamp(5, 50);
          } else if (exercise.type == ExerciseType.walkingLunge) {
            roundedReps = roundedReps.clamp(5, 30);
          } else {
            roundedReps = roundedReps.clamp(20, 80);
          }
        }
        if (exercise.type == ExerciseType.burpee) {
          roundedReps = roundedReps.clamp(20, 120);
        } else if (exercise.type == ExerciseType.pushUp) {
          roundedReps = roundedReps.clamp(40, 160);
        } else if (exercise.type == ExerciseType.squat) {
          roundedReps = roundedReps.clamp(48, 160);
        } else if (exercise.type == ExerciseType.walkingLunge) {
          roundedReps = roundedReps.clamp(40, 160);
        } else {
          roundedReps = roundedReps.clamp(48, 160);
        }
        computedTargets[exercise.type] = roundedReps;
      }
    }

    return computedTargets;
  }

  // Hàm bổ trợ lấy Calo chuẩn trên 1 Rep của người 70kg
  double _getCaloPerRep(ExerciseType type) => switch (type) {
    ExerciseType.burpee => 0.8, // Rất nặng, tốn nhiều năng lượng
    ExerciseType.pushUp => 0.35, // Trung bình (8.5 cpm / 24 reps)
    ExerciseType.walkingLunge =>
      0.4, // Trọng lượng dồn 1 chân (8.0 cpm / 20 reps)
    ExerciseType.squat => 0.35, // Nhóm cơ lớn (7.0 cpm / 20 reps)
    ExerciseType.jumpingJack =>
      0.25, // Động tác nhanh, calo mỗi cái thấp (10.0 cpm / 40 reps)
    ExerciseType.plank =>
      0.0, // Bài tập giữ trạng thái (tính theo giây, không tính rep)
  };

  // B. SINH LỊCH TRÌNH 7 NGÀY THÍCH ỨNG THEO MỤC TIÊU & THỂ TRẠNG
  List<Map<String, dynamic>> _generateAdaptiveSchedule(
    String goal,
    double bmi,
    int age,
  ) {
    bool avoidBurpee = (bmi >= 25.0 || age >= 45);

    if (goal == 'lose') {
      return [
        {
          'day': 1,
          'title': 'Đốt mỡ khởi động',
          'isRest': false,
          'exercises': [
            {
              'type': ExerciseType.jumpingJack,
              'reason':
                  'Nhảy Jumping Jack nhịp nhàng để làm nóng cơ thể và kích hoạt tuần hoàn tim mạch.',
            },
            {
              'type': avoidBurpee ? ExerciseType.pushUp : ExerciseType.burpee,
              'reason': avoidBurpee
                  ? 'Chống đẩy giúp đốt calo thân trên an toàn và tránh gây lực nén tiếp đất đột ngột lên khớp chân.'
                  : 'Burpee bộc phát giúp đẩy tối đa hiệu suất tiêu hao năng lượng trong ngày khởi đầu.',
            },
          ],
        },
        {
          'day': 2,
          'title': 'Kích hoạt bụng core',
          'isRest': false,
          'exercises': [
            {
              'type': ExerciseType.plank,
              'reason':
                  'Plank để củng cố sức mạnh nhóm cơ core trung tâm bụng lưng.',
            },
            {
              'type': ExerciseType.squat,
              'reason':
                  'Squat đùi mông để tăng khả năng đốt mỡ thụ động thông qua cơ bắp chân.',
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
              'type': ExerciseType.jumpingJack,
              'reason':
                  'Jumping Jack tăng cường hoạt động hô hấp và tuần hoàn tim mạch.',
            },
            {
              'type': ExerciseType.walkingLunge,
              'reason':
                  'Lunge bước đi săn chắc đùi mông và cải thiện tính thăng bằng khớp hông.',
            },
          ],
        },
        {
          'day': 5,
          'title': 'Sức mạnh & Bộc phát',
          'isRest': false,
          'exercises': [
            {
              'type': ExerciseType.squat,
              'reason':
                  'Gánh đùi Squat sâu giúp tăng cường cơ lực và bôi trơn ổ khớp chân.',
            },
            {
              'type': avoidBurpee ? ExerciseType.pushUp : ExerciseType.burpee,
              'reason': avoidBurpee
                  ? 'Chống đẩy rèn sức chịu đựng cơ đẩy ngực tay mà không gây quá tải cho khớp gối.'
                  : 'Burpee cường độ cao giúp tối ưu hóa calo thâm hụt.',
            },
          ],
        },
        {
          'day': 6,
          'title': 'Siết eo & Sức bền',
          'isRest': false,
          'exercises': [
            {
              'type': ExerciseType.plank,
              'reason':
                  'Thử thách Plank giữ thẳng lưng giúp định hình vòng eo thon nhỏ.',
            },
            {
              'type': ExerciseType.pushUp,
              'reason': 'Chống đẩy duy trì phom ngực và vai săn chắc.',
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
              'type': ExerciseType.pushUp,
              'reason':
                  'Chống đẩy tập trung kích thích phát triển nhóm cơ ngực lớn, vai trước và tay sau.',
            },
            {
              'type': ExerciseType.plank,
              'reason':
                  'Plank tăng độ vững chãi cho core bụng để chịu lực cơ thể tốt hơn.',
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
                  'Squat kích hoạt sản sinh hormone tăng trưởng tự nhiên để phát triển nhóm cơ lớn nhất cơ thể.',
            },
            {
              'type': ExerciseType.walkingLunge,
              'reason':
                  'Walking Lunge tăng sức mạnh độc lập từng chân và cải thiện tính linh hoạt khớp hông.',
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
              'type': avoidBurpee ? ExerciseType.pushUp : ExerciseType.burpee,
              'reason': avoidBurpee
                  ? 'Chống đẩy rèn luyện trương lực cơ phần trên an toàn khi không thể nhảy burpee.'
                  : 'Burpee thử thách sức bền cơ bắp bộc phát cường độ cao toàn diện.',
            },
            {
              'type': ExerciseType.squat,
              'reason':
                  'Squat nhịp độ đều đặn để duy trì thể tích bơm máu vào các nhóm cơ chân.',
            },
          ],
        },
        {
          'day': 5,
          'title': 'Core bụng & Sức chống chịu',
          'isRest': false,
          'exercises': [
            {
              'type': ExerciseType.plank,
              'reason':
                  'Plank tăng sức bền tĩnh cho cột sống và nhóm cơ sườn chậu.',
            },
            {
              'type': ExerciseType.walkingLunge,
              'reason':
                  'Lunge bước chậm rèn luyện khả năng giữ thăng bằng di động và dẻo dai cơ mông.',
            },
          ],
        },
        {
          'day': 6,
          'title': 'Sức bền Thân trên',
          'isRest': false,
          'exercises': [
            {
              'type': ExerciseType.pushUp,
              'reason':
                  'Chống đẩy siết cơ ngực tay vai, gia tăng thể tích cơ nạc thân trên.',
            },
            {
              'type': ExerciseType.jumpingJack,
              'reason':
                  'Jumping Jack kích hoạt bơm máu toàn thân tăng tốc độ chuyển hóa dưỡng chất.',
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
      // maintain - Giữ dáng linh hoạt
      return [
        {
          'day': 1,
          'title': 'Khởi động & Core bụng',
          'isRest': false,
          'exercises': [
            {
              'type': ExerciseType.plank,
              'reason':
                  'Plank siết eo nhẹ nhàng duy trì bụng phẳng và tư thế đứng thẳng đẹp mắt.',
            },
            {
              'type': ExerciseType.jumpingJack,
              'reason':
                  'Jumping Jack vận động tim mạch nhẹ nhàng để tiêu hao mỡ thừa tích tụ.',
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
                  'Squat vừa sức duy trì cơ đùi mông săn gọn và linh hoạt ổ khớp gối.',
            },
            {
              'type': ExerciseType.walkingLunge,
              'reason':
                  'Walking Lunge tăng độ thăng bằng di động cho cơ khớp hông háng.',
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
          'title': 'Sức mạnh vừa sức',
          'isRest': false,
          'exercises': [
            {
              'type': ExerciseType.pushUp,
              'reason':
                  'Chống đẩy duy trì cơ ngực bả vai săn chắc tự nhiên không bị chảy xệ.',
            },
            {
              'type': ExerciseType.squat,
              'reason':
                  'Squat nhẹ nhàng để bôi trơn khớp gối và tăng tuần hoàn máu chân.',
            },
          ],
        },
        {
          'day': 5,
          'title': 'Sức bền toàn diện',
          'isRest': false,
          'exercises': [
            {
              'type': ExerciseType.jumpingJack,
              'reason':
                  'Jumping Jack rèn luyện khả năng hô hấp và tăng tính linh hoạt toàn thân.',
            },
            {
              'type': ExerciseType.plank,
              'reason':
                  'Plank giữ vững liên kết cột sống lưng tránh đau mỏi do ngồi văn phòng nhiều.',
            },
          ],
        },
        {
          'day': 6,
          'title': 'Linh hoạt & Định hình',
          'isRest': false,
          'exercises': [
            {
              'type': ExerciseType.walkingLunge,
              'reason': 'Lunge bước đi nhẹ nhàng làm thon gọn bắp đùi mông.',
            },
            {
              'type': ExerciseType.pushUp,
              'reason':
                  'Chống đẩy duy trì sức chịu lực cổ tay và cơ ngực vai khỏe khoắn.',
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

  @override
  Widget build(BuildContext context) {
    // 1. Tính toán BMR & TDEE theo Mifflin-St Jeor khoa học
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

    // 2. Tính toán BMI sinh học
    double bmi = _height > 0
        ? _weight / ((_height / 100) * (_height / 100))
        : 0.0;

    // Đánh giá trạng thái thể trạng
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

    // 3. SINH BÀI TẬP ĐỀ XUẤT VÀ LỊCH TRÌNH THÍCH ỨNG DỰA TRÊN THỂ TRẠNG THỰC TẾ
    final rawSchedule = _generateAdaptiveSchedule(
      _selectedGoal,
      bmi,
      _age,
    );
    final adaptiveSchedule = _postProcessAdaptiveSchedule(rawSchedule);
    final int todayIndex = DateTime.now().weekday - 1;
    final int safeTodayIndex = 7 + todayIndex;
    final selectedDayIndex = _selectedDayIndex.clamp(
      0,
      adaptiveSchedule.length - 1,
    );
    final selectedDayData = adaptiveSchedule[selectedDayIndex];
    final selectedDayDate = _getSelectedDayDate(selectedDayIndex);

    // 4. Tính toán số lượng mục tiêu (Rep/Giây) dựa trên TDEE
    final scientificTargets = _calculateScientificReps(
      _weight,
      _height,
      _age,
      _selectedGoal,
      _gender,
    );
    final double caloriesPerExercise = targetWorkoutCalories / 4;

    return Scaffold(
      body: SafeArea(
        child: _isLoading
            ? const Center(
                child: CircularProgressIndicator(color: AppTheme.neonGreen),
              )
            : CustomScrollView(
                slivers: [
                  // 1. THANH TIÊU ĐỀ
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

                  // 2. KHU VỰC THÔNG SỐ CƠ THỂ
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20.0,
                        vertical: 10.0,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Hộp thông số thể trạng
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: AppTheme.glassDecoration(
                              color: AppTheme.cardBackground.withValues(
                                alpha: 0.5,
                              ),
                              borderRadius: 20,
                            ),
                            child: Column(
                              children: [
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
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
                                          borderRadius: BorderRadius.circular(
                                            10,
                                          ),
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
                                const Divider(
                                  color: Colors.white12,
                                  height: 24,
                                ),

                                // Thang đo BMI
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
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
                                          color: bmiColor.withValues(
                                            alpha: 0.4,
                                          ),
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

                                const Divider(
                                  color: Colors.white12,
                                  height: 24,
                                ),

                                // BMR & TDEE khoa học
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    const Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
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
                                      crossAxisAlignment:
                                          CrossAxisAlignment.end,
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

                                const Divider(
                                  color: Colors.white12,
                                  height: 24,
                                ),

                                // Mục tiêu đốt calo của buổi tập
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
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
                              ],
                            ),
                          ),
                          const SizedBox(height: 20),

                          // LỜI KHUYÊN CỦA HLV AI
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
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
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
                                          color: Colors.white.withValues(
                                            alpha: 0.85,
                                          ),
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

                          // 3. CHỌN MỤC TIÊU TẬP LUYỆN
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
                              color: const Color(0xFF1E293B), // Slate 800
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
                                  child: _buildGoalChip(
                                    'maintain',
                                    '⚖️ Giữ dáng',
                                  ),
                                ),
                                Expanded(
                                  child: _buildGoalChip('build', '💪 Tăng cơ'),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 20),
                          // DỜI LÊN ĐÂY: LỊCH TRÌNH CHỌN THỨ TRONG TUẦN (HIỆN CHO TẤT CẢ CÁC MỤC TIÊU)
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
                          // 1. Sleek week tab selector
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
                                      // Khi đổi tuần, tự động chọn ngày Thứ Hai của tuần đó
                                      _selectedDayIndex = weekIdx * 7;
                                    });
                                    final selectedDate = _getSelectedDayDate(_selectedDayIndex);
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
                                            ? AppTheme.neonGreen.withValues(alpha: 0.4)
                                            : Colors.white.withValues(alpha: 0.05),
                                        width: 1,
                                      ),
                                    ),
                                    child: Center(
                                      child: Text(
                                        labels[weekIdx],
                                        style: TextStyle(
                                          color: isSelected ? AppTheme.neonGreen : Colors.white60,
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
                              final cellWidth =
                                  (constraints.maxWidth - (6 * 6)) /
                                  7; // Spacing 6px giữa 7 cột

                              return Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: List.generate(7, (colIndex) {
                                  final dayGlobalIndex = (_selectedWeekIndex * 7) + colIndex;
                                  final isToday = dayGlobalIndex == safeTodayIndex;
                                  final isSelected = dayGlobalIndex == selectedDayIndex;
                                  final isCompleted = _isDayWorkoutCompleted(
                                    dayGlobalIndex,
                                    adaptiveSchedule,
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
                                      _loadCompletedExercisesForDay(
                                        selectedDate,
                                      );
                                      _loadMealLogsForDay(selectedDate);
                                    },
                                    child: AnimatedContainer(
                                      duration: const Duration(
                                        milliseconds: 200,
                                      ),
                                      width: cellWidth,
                                      height: 70, // Tăng chiều cao lên một chút để hiển thị số ngày đẹp mắt
                                      decoration: isSelected
                                          ? BoxDecoration(
                                              gradient: const LinearGradient(
                                                colors: [
                                                  Color(0xFF3B82F6),
                                                  Color(0xFF1D4ED8),
                                                ], // Gradient xanh dương hiện đại nổi bật
                                                begin: Alignment.topCenter,
                                                end: Alignment.bottomCenter,
                                              ),
                                              borderRadius:
                                                  BorderRadius.circular(12),
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
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                              border: Border.all(
                                                color: isToday
                                                    ? AppTheme.neonGreen
                                                          .withValues(
                                                            alpha: 0.3,
                                                          )
                                                    : Colors.white.withValues(
                                                        alpha: 0.05,
                                                      ),
                                                width: 1,
                                              ),
                                            ),
                                      child: Column(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          Text(
                                            shortWeekdays[colIndex],
                                            style: TextStyle(
                                              color: isSelected
                                                  ? Colors.white
                                                  : (isToday
                                                        ? AppTheme.neonGreen
                                                        : Colors.white
                                                              .withValues(
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
                                          // Dấu chấm tròn báo hiệu đã hoàn thành bài tập hoặc ngày nghỉ ngơi
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
                                  key: const PageStorageKey<String>(
                                    'workout_panel',
                                  ),
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
                                          selectedDayData['isRest'] as bool? ??
                                          false;

                                      if (isRest) {
                                        return const Text(
                                          'Hôm nay: Nghỉ ngơi & phục hồi',
                                          style: TextStyle(
                                            color: Colors.white70,
                                            fontSize: 11,
                                          ),
                                        );
                                      }

                                      int totalExercises =
                                          currentExercises.length;
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
                                              completedCount ==
                                                      totalExercises &&
                                                  totalExercises > 0
                                              ? AppTheme.neonGreen
                                              : Colors.white70,
                                          fontSize: 11,
                                          fontWeight:
                                              completedCount ==
                                                      totalExercises &&
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
                                        margin: const EdgeInsets.only(
                                          bottom: 12,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Colors.black12,
                                          borderRadius: BorderRadius.circular(
                                            10,
                                          ),
                                          border: Border.all(
                                            color: Colors.white10,
                                          ),
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
                                            selectedDayData['isRest']
                                                as bool? ??
                                            false;
                                        if (isRest) {
                                          return Container(
                                            width: double.infinity,
                                            padding: const EdgeInsets.all(16),
                                            decoration: BoxDecoration(
                                              color: Colors.black12,
                                              borderRadius:
                                                  BorderRadius.circular(12),
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
                                          );
                                        }
                                        return const SizedBox.shrink();
                                      },
                                    ),
                                    Builder(
                                      builder: (context) {
                                        final List<dynamic> currentExercises =
                                            selectedDayData['exercises']
                                                as List<dynamic>? ??
                                            [];
                                        final bool isRest =
                                            selectedDayData['isRest']
                                                as bool? ??
                                            false;
                                        if (isRest ||
                                            currentExercises.isEmpty) {
                                          return const SizedBox.shrink();
                                        }

                                        int totalExercises =
                                            currentExercises.length;
                                        int completedCount = 0;
                                        final List<String> completedList = [];
                                        final List<String> missingList = [];

                                        for (var rec in currentExercises) {
                                          final ExerciseType type =
                                              rec['type'] as ExerciseType;
                                          final originalExercise =
                                              ExerciseDetail.defaultExercises
                                                  .firstWhere(
                                                    (e) => e.type == type,
                                                  );
                                          final bool isCompleted =
                                              _isExerciseCompletedForDay(
                                                type,
                                                selectedDayDate,
                                              );
                                          if (isCompleted) {
                                            completedCount++;
                                            completedList.add(
                                              originalExercise.name,
                                            );
                                          } else {
                                            missingList.add(
                                              originalExercise.name,
                                            );
                                          }
                                        }

                                        return Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              mainAxisAlignment:
                                                  MainAxisAlignment
                                                      .spaceBetween,
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
                                              borderRadius:
                                                  BorderRadius.circular(4),
                                              child: LinearProgressIndicator(
                                                value:
                                                    (completedCount /
                                                    totalExercises),
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
                                                    completedCount ==
                                                        totalExercises
                                                    ? AppTheme.neonGreen
                                                          .withValues(
                                                            alpha: 0.05,
                                                          )
                                                    : AppTheme.errorRed
                                                          .withValues(
                                                            alpha: 0.05,
                                                          ),
                                                borderRadius:
                                                    BorderRadius.circular(10),
                                                border: Border.all(
                                                  color:
                                                      completedCount ==
                                                          totalExercises
                                                      ? AppTheme.neonGreen
                                                            .withValues(
                                                              alpha: 0.15,
                                                            )
                                                      : AppTheme.errorRed
                                                            .withValues(
                                                              alpha: 0.15,
                                                            ),
                                                ),
                                              ),
                                              child: Row(
                                                children: [
                                                  Icon(
                                                    completedCount ==
                                                            totalExercises
                                                        ? Icons.stars_rounded
                                                        : Icons
                                                              .warning_amber_rounded,
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
                                                      completedCount ==
                                                              totalExercises
                                                          ? 'Tuyệt vời! Bạn đã hoàn thành toàn bộ bài tập của ngày này!'
                                                          : 'Bạn đang thiếu bài tập: ${missingList.join(", ")}.',
                                                      style: TextStyle(
                                                        color:
                                                            completedCount ==
                                                                totalExercises
                                                            ? AppTheme.neonGreen
                                                            : AppTheme.errorRed,
                                                        fontSize: 10.5,
                                                        fontWeight:
                                                            FontWeight.bold,
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
                                            ...currentExercises.map((rec) {
                                              return _buildExerciseCard(
                                                rec as Map<String, dynamic>,
                                                scientificTargets,
                                                caloriesPerExercise,
                                                selectedDayIndex ==
                                                    safeTodayIndex,
                                                selectedDayDate,
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

  // Thẻ bài tập đề xuất dùng chung
  Widget _buildExerciseCard(
    Map<String, dynamic> rec,
    Map<ExerciseType, int> scientificTargets,
    double caloriesPerExercise,
    bool allowWorkoutAction,
    DateTime selectedDayDate,
  ) {
    final ExerciseType type = rec['type'] as ExerciseType;
    final String reason = rec['reason'] as String;

    // Tính toán số lượng rep mục tiêu thực tế dựa trên khoa học (để đè lên mục tiêu tĩnh ban đầu)
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

    final originalExercise = ExerciseDetail.defaultExercises.firstWhere(
      (e) => e.type == type,
    );

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: AppTheme.glassDecoration(
        color: AppTheme.cardBackground.withValues(alpha: 0.3),
        borderRadius: 20,
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
                  Expanded(
                    child: Text(
                      'CHỌN SỐ LƯỢNG KHÁC:',
                      style: const TextStyle(
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
                        await _loadHeavyExercises();
                        if ((result == true || result == 'complete') &&
                            mounted) {
                          // Thực hiện cập nhật trạng thái UI cục bộ (nếu cần offline)
                          _toggleExerciseCompletedForDay(
                            type,
                            selectedDayDate,
                            finalTargetCount,
                            isManual: false,
                          );
                          // Đồng thời tải lại dữ liệu chuẩn xác từ Database về
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
    if (bmi >= 25.0) {
      return goal == 'lose';
    } else if (bmi < 18.5) {
      return goal == 'build';
    } else {
      return goal == 'maintain' || goal == 'build';
    }
  }

  Widget _buildGoalChip(String goalKey, String label) {
    double bmi = _height > 0
        ? _weight / ((_height / 100) * (_height / 100))
        : 0.0;

    final isAllowed = isGoalAllowedForBmi(goalKey, bmi);
    final isSelected = _selectedGoal == goalKey;

    return GestureDetector(
      onTap: isAllowed
          ? () => _updateGoal(goalKey)
          : () {
              String reason = '';
              if (bmi >= 25.0) {
                reason =
                    'Mục tiêu này bị khóa. Thể trạng Thừa cân/Béo phì cần ưu tiên Giảm cân để bảo vệ khớp gối!';
              } else if (bmi < 18.5) {
                reason =
                    'Mục tiêu này bị khóa. Thể trạng Thiếu cân cần ưu tiên Tăng cơ để cải thiện thể hình!';
              } else {
                reason =
                    'BMI Cân đối không cần giảm cân. Hãy chọn Giữ dáng hoặc Tăng cơ!';
              }
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('🔒 $reason'),
                  backgroundColor: Colors.grey[900],
                  duration: const Duration(seconds: 3),
                ),
              );
            },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: isSelected
            ? BoxDecoration(
                gradient: LinearGradient(
                  colors: goalKey == 'lose'
                      ? const [
                          Color(0xFFFF6B6B),
                          Color(0xFFFF4500),
                        ] // Đỏ cam – giảm cân
                      : goalKey == 'maintain'
                      ? const [
                          Color(0xFF60A5FA),
                          Color(0xFF3B82F6),
                        ] // Xanh dương – giữ dáng
                      : const [
                          Color(0xFF34D399),
                          Color(0xFF059669),
                        ], // Xanh lá – tăng cơ
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color:
                        (goalKey == 'lose'
                                ? const Color(0xFFFF6B6B)
                                : goalKey == 'maintain'
                                ? const Color(0xFF3B82F6)
                                : const Color(0xFF34D399))
                            .withValues(alpha: 0.35),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ],
              )
            : BoxDecoration(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(12),
              ),
        child: Center(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!isAllowed) ...[
                Icon(
                  Icons.lock_outline,
                  size: 13,
                  color: Colors.white.withValues(alpha: 0.25),
                ),
                const SizedBox(width: 4),
              ],
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                  style: TextStyle(
                    color: isSelected
                        ? Colors.white
                        : (isAllowed
                              ? Colors.white.withValues(alpha: 0.6)
                              : Colors.white.withValues(alpha: 0.2)),
                    fontWeight: isSelected
                        ? FontWeight.bold
                        : FontWeight.normal,
                    fontSize: 12.5,
                    decoration: isAllowed
                        ? TextDecoration.none
                        : TextDecoration.lineThrough,
                    decorationColor: Colors.white.withValues(alpha: 0.3),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
