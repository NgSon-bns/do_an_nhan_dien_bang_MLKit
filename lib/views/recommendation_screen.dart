import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/theme/app_theme.dart';
import '../models/exercise.dart';
import '../services/auth_service.dart';
import '../services/database_service.dart';
import '../services/workout_draft_service.dart';
import 'workout/workout_screen.dart';

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
  String _userName = '';
  bool _isLoading = true;
  String _selectedGoal = 'maintain'; // 'lose', 'maintain', 'build'
  int _selectedDayIndex = 0; // Chọn ngày trong lịch trình giảm cân (0 - 6)
  final Map<ExerciseType, bool> _noSplitTargets = {};
  final Map<ExerciseType, int> _selectedTargets = {};
  final Map<ExerciseType, bool> _expandedTargetSelectors = {};
  final Map<String, Set<String>> _completedExerciseKeysByDay = {};

  @override
  void initState() {
    super.initState();
    _selectedDayIndex = DateTime.now().weekday - 1;
    _loadUserProfile();
    _loadCompletedExercisesForDay(_getSelectedDayDate(_selectedDayIndex));
    _refreshTodayDraftWorkout();
  }

  Future<void> _refreshTodayDraftWorkout() async {
    final draft = await _workoutDraftService.getTodayDraftWorkout();
    if (mounted) {
      setState(() {
        _todayDraftWorkout = draft;
      });
    }
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
          _userName = profile['full_name'] ?? 'Trainer';
          _weight = (profile['weight'] as num?)?.toDouble() ?? 0.0;
          _height = (profile['height'] as num?)?.toDouble() ?? 0.0;
          _age = (profile['age'] as num?)?.toInt() ?? 0;

          if (_weight == 0.0) _weight = 65.0;
          if (_height == 0.0) _height = 170.0;
          if (_age == 0) _age = 25;

          // Đọc mục tiêu tập luyện từ database nếu có lưu trước đó
          final String? dbGoal = profile['goal'] ?? profile['fitness_goal'];
          if (dbGoal != null) {
            _selectedGoal = dbGoal;
          } else {
            // Tự chọn mặc định dựa trên BMI
            double bmi = _weight / ((_height / 100) * (_height / 100));
            if (bmi >= 25.0) {
              _selectedGoal = 'lose';
            } else if (bmi < 18.5) {
              _selectedGoal = 'build';
            } else {
              _selectedGoal = 'maintain';
            }
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
  ) async {
    setState(() {
      _isLoading = true;
    });

    try {
      if (_isSupabaseInitialized) {
        final client = Supabase.instance.client;
        final userId = client.auth.currentUser?.id;
        if (userId != null) {
          await client
              .from('profiles')
              .update({'height': newHeight, 'weight': newWeight, 'age': newAge})
              .eq('id', userId);
        }
      }

      setState(() {
        _height = newHeight;
        _weight = newWeight;
        _age = newAge;
      });
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
              .from('profiles')
              .update({'goal': newGoal})
              .eq('id', userId);
        } catch (dbError) {
          debugPrint(
            'Thử lưu cột goal thất bại (có thể thiếu cột), thử fitness_goal: $dbError',
          );
          try {
            await client
                .from('profiles')
                .update({'fitness_goal': newGoal})
                .eq('id', userId);
          } catch (_) {}
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
    return startOfToday.add(Duration(days: index - todayIndex));
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

  void _toggleExerciseCompletedForDay(
    ExerciseType type,
    DateTime day,
    int targetCount,
  ) {
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

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
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
                _updatePhysicalStats(h, w, a);
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
    );
  }

  // Thuật toán tính mục tiêu reps/seconds dựa trên TDEE & Mifflin-St Jeor theo chuẩn khoa học thể thao
  Map<ExerciseType, int> _calculateScientificReps(
    double weight,
    double height,
    int age,
    String goal,
  ) {
    // 1. Tính toán các chỉ số nền tảng
    double bmi = weight / ((height / 100) * (height / 100));

    double bmr = (10 * weight) + (6.25 * height) - (5 * age) - 78;
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

        // Nới rộng khoảng clamp để phân biệt rõ người khỏe/yếu, nặng/nhẹ cân
        // giới hạn theo ACSM
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

  // A. ĐỀ XUẤT BÀI TẬP ĐỘNG THEO THỂ TRẠNG (BMI & TUỔI)
  List<Map<String, dynamic>> _generateAdaptiveDailyExercises(
    double bmi,
    int age,
    String goal,
  ) {
    bool isOlder = age >= 45;
    bool isOverweight = bmi >= 25.0;
    bool isUnderweight = bmi < 18.5;

    // 1. Thể trạng THIẾU CÂN: Tập trung xây dựng cơ bắp (strength), loại bỏ hoàn toàn cardio nhảy quá mức
    if (isUnderweight) {
      return [
        {
          'type': ExerciseType.pushUp,
          'reason':
              'Chống đẩy tập trung lực đẩy, kích thích các thớ cơ ngực và tay vai nở nang ở cơ thể gầy.',
        },
        {
          'type': ExerciseType.squat,
          'reason':
              'Squat đùi mông giúp xây dựng khối cơ nạc lớn nhất cơ thể, hỗ trợ tăng cân và tăng cơ bền vững.',
        },
        {
          'type': ExerciseType.walkingLunge,
          'reason':
              'Walking Lunge tăng khả năng chịu lực độc lập từng chân, rèn sức mạnh đối xứng khớp chân.',
        },
        {
          'type': ExerciseType.plank,
          'reason':
              'Plank giúp săn chắc và khỏe cơ cốt lõi lưng bụng, tạo vóc dáng đứng thẳng đẹp hơn.',
        },
      ];
    }

    // 2. Thể trạng LỚN TUỔI (Age >= 45): Tránh Burpee hoàn toàn để bảo vệ tim mạch và khớp gối chịu lực đột ngột
    if (isOlder) {
      return [
        {
          'type': ExerciseType.plank,
          'reason':
              'Plank là bài tập core an toàn và tối ưu tuyệt đối cho người trung niên, không lo xóc đĩa đệm lưng.',
        },
        {
          'type': ExerciseType.squat,
          'reason':
              'Squat nhẹ nhàng giúp kích thích dịch khớp gối, tăng cường cơ nâng đỡ đùi cho người lớn tuổi.',
        },
        {
          'type': ExerciseType.walkingLunge,
          'reason':
              'Lunge chậm bước giúp tăng khả năng giữ thăng bằng và dẻo dai cơ hông đùi.',
        },
        {
          'type': ExerciseType.pushUp,
          'reason':
              'Chống đẩy để duy trì lực cơ ngực vai đẩy khỏe mạnh cho cơ thể người lớn tuổi.',
        },
      ];
    }

    // 3. Thể trạng THỪA CÂN/BÉO PHÌ: Tránh Burpee để bảo vệ khớp gối chịu áp lực cơ thể nặng
    if (isOverweight) {
      if (goal == 'lose') {
        return [
          {
            'type': ExerciseType.jumpingJack,
            'reason':
                'Jumping Jack là bài tập nhảy nhẹ nhàng hơn Burpee, giúp đốt calo hiệu quả và an toàn cho người thừa cân.',
          },
          {
            'type': ExerciseType.squat,
            'reason':
                'Squat tăng lực cơ đùi mông nhằm bảo vệ khớp gối khỏi gánh nặng trọng lượng cơ thể.',
          },
          {
            'type': ExerciseType.plank,
            'reason':
                'Plank tăng sức bền core bụng để tránh võng lưng, giảm đau mỏi lưng dưới do mỡ bụng.',
          },
          {
            'type': ExerciseType.pushUp,
            'reason':
                'Chống đẩy tập trung calo thân trên, bảo toàn gối khỏi phản lực tiếp đất.',
          },
        ];
      }
    }

    // 4. Thể trạng CÂN ĐỐI thông thường
    if (goal == 'lose') {
      return [
        {
          'type': ExerciseType.jumpingJack,
          'reason':
              'Nhảy Jumping Jack nhanh liên tục giúp kích hoạt quá trình tiêu hao năng lượng toàn thân.',
        },
        {
          'type': ExerciseType.burpee,
          'reason':
              'Burpee đốt calo cực đỉnh, giúp cơ thể tăng tốc tiêu mỡ thừa bền bỉ sau tập.',
        },
        {
          'type': ExerciseType.squat,
          'reason':
              'Squat đùi mông kích hoạt giải phóng calo qua các nhóm cơ lớn nhất cơ thể.',
        },
        {
          'type': ExerciseType.plank,
          'reason':
              'Plank siết chặt bụng để tạo cơ bụng phẳng và săn chắc cơ liên sườn.',
        },
      ];
    } else if (goal == 'build') {
      return [
        {
          'type': ExerciseType.pushUp,
          'reason':
              'Chống đẩy tạo phom cơ ngực vai nở rộng và bắp tay sau sắc nét.',
        },
        {
          'type': ExerciseType.squat,
          'reason':
              'Squat kích hoạt sản sinh hocmon nam tăng trưởng để hỗ trợ tăng cơ toàn diện.',
        },
        {
          'type': ExerciseType.walkingLunge,
          'reason':
              'Lunge bước đi dồn lực độc lập từng đùi, giúp cơ mông săn chắc bộc phá.',
        },
        {
          'type': ExerciseType.burpee,
          'reason':
              'Burpee nâng cao sức mạnh bộc phát toàn thân và thể lực bắp thịt chịu đựng.',
        },
      ];
    } else {
      // Giữ dáng (maintain) thông thường
      return [
        {
          'type': ExerciseType.plank,
          'reason':
              'Giữ Plank đều đặn hàng ngày để giữ cơ bụng phẳng lỳ và thẳng đứng cột sống.',
        },
        {
          'type': ExerciseType.walkingLunge,
          'reason':
              'Walking Lunge làm săn gọn mông đùi và cải thiện khả năng giữ thăng bằng di động.',
        },
        {
          'type': ExerciseType.pushUp,
          'reason':
              'Chống đẩy vừa sức duy trì phom ngực và trương lực cơ tay khỏe khoắn.',
        },
        {
          'type': ExerciseType.squat,
          'reason':
              'Squat để giữ khớp chân linh hoạt và săn chắc vùng hông dưới.',
        },
      ];
    }
  }

  // B. SINH LỊCH TRÌNH GIẢM CÂN 7 NGÀY THÍCH ỨNG THEO THỂ TRẠNG (BMI & TUỔI)
  List<Map<String, dynamic>> _generateAdaptiveWeightLossSchedule(
    double bmi,
    int age,
  ) {
    bool avoidBurpee = (bmi >= 25.0 || age >= 45);

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
  }

  @override
  Widget build(BuildContext context) {
    // 1. Tính toán BMR & TDEE theo Mifflin-St Jeor khoa học
    final double bmr = _height > 0
        ? (10 * _weight) + (6.25 * _height) - (5 * _age) - 78
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
    final recommendedList = _generateAdaptiveDailyExercises(
      bmi,
      _age,
      _selectedGoal,
    );
    final adaptiveWeightLossSchedule = _generateAdaptiveWeightLossSchedule(
      bmi,
      _age,
    );
    final int todayIndex = DateTime.now().weekday - 1;
    final int safeTodayIndex = todayIndex.clamp(
      0,
      adaptiveWeightLossSchedule.length - 1,
    );
    final List<String> weekdays = [
      'Thứ Hai',
      'Thứ Ba',
      'Thứ Tư',
      'Thứ Năm',
      'Thứ Sáu',
      'Thứ Bảy',
      'Chủ Nhật',
    ];
    final selectedDayIndex = _selectedDayIndex.clamp(
      0,
      adaptiveWeightLossSchedule.length - 1,
    );
    final selectedDayData = adaptiveWeightLossSchedule[selectedDayIndex];
    final selectedDayDate = _getSelectedDayDate(selectedDayIndex);

    // 4. Tính toán số lượng mục tiêu (Rep/Giây) dựa trên TDEE
    final scientificTargets = _calculateScientificReps(
      _weight,
      _height,
      _age,
      _selectedGoal,
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
                          Row(
                            children: [
                              Expanded(
                                child: _buildGoalChip('lose', '🎯 Giảm cân'),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: _buildGoalChip(
                                  'maintain',
                                  '⚖️ Giữ dáng',
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: _buildGoalChip('build', '💪 Tăng cơ'),
                              ),
                            ],
                          ),
                          const SizedBox(height: 28),

                          // NẾU GIẢM CÂN: HIỂN THỊ LỊCH TRÌNH CHO THỨ HÔM NAY
                          if (isLoseWeight) ...[
                            const Row(
                              children: [
                                Icon(
                                  Icons.calendar_month,
                                  color: AppTheme.neonGreen,
                                  size: 18,
                                ),
                                SizedBox(width: 6),
                                Text(
                                  'LỊCH TRÌNH HÔM NAY',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: AppTheme.neonGreen,
                                    letterSpacing: 1.5,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            SizedBox(
                              height: 70,
                              child: ListView.builder(
                                scrollDirection: Axis.horizontal,
                                itemCount: weekdays.length,
                                itemBuilder: (context, index) {
                                  final isToday = index == safeTodayIndex;
                                  final isSelected = index == selectedDayIndex;
                                  return GestureDetector(
                                    onTap: () {
                                      setState(() {
                                        _selectedDayIndex = index;
                                      });
                                      _loadCompletedExercisesForDay(
                                        _getSelectedDayDate(index),
                                      );
                                    },
                                    child: Container(
                                      width: 92,
                                      margin: const EdgeInsets.only(right: 8),
                                      decoration: isSelected
                                          ? AppTheme.glassDecoration(
                                              color: AppTheme.neonGreen
                                                  .withValues(alpha: 0.2),
                                              borderRadius: 14,
                                            ).copyWith(
                                              border: Border.all(
                                                color: AppTheme.neonGreen,
                                                width: 1.5,
                                              ),
                                            )
                                          : AppTheme.glassDecoration(
                                              color: Colors.white.withValues(
                                                alpha: 0.04,
                                              ),
                                              borderRadius: 14,
                                            ),
                                      child: Column(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          Text(
                                            weekdays[index],
                                            style: TextStyle(
                                              color: isSelected
                                                  ? AppTheme.neonGreen
                                                  : Colors.grey,
                                              fontSize: 10.5,
                                              fontWeight: isSelected
                                                  ? FontWeight.bold
                                                  : FontWeight.normal,
                                            ),
                                            textAlign: TextAlign.center,
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            isToday ? 'Hôm nay' : '',
                                            style: const TextStyle(
                                              color: Colors.white70,
                                              fontSize: 10,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                            const SizedBox(height: 20),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 12,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.04),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.white10),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'TIÊU ĐIỂM ${weekdays[selectedDayIndex].toUpperCase()}:',
                                    style: const TextStyle(
                                      color: Colors.grey,
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    selectedDayData['title']
                                        .toString()
                                        .toUpperCase(),
                                    style: const TextStyle(
                                      color: AppTheme.neonGreen,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ] else ...[
                            // NẾU GIỮ DÁNG HOẶC TĂNG CƠ: KHÔNG HIỆN LỊCH TRÌNH, CHỈ HIỆN DANH SÁCH KHUYÊN TẬP HÀNG NGÀY
                            const Text(
                              'DANH SÁCH BÀI TẬP ĐỀ XUẤT CÁ NHÂN HÓA',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.neonGreen,
                                letterSpacing: 1.5,
                              ),
                            ),
                          ],
                          const SizedBox(height: 16),
                        ],
                      ),
                    ),
                  ),

                  // 5. HIỂN THỊ DANH SÁCH BÀI TẬP ĐỀ XUẤT HOẶC KẾ HOẠCH NGÀY
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 20.0),
                    sliver: _buildExercisesSliverList(
                      isLoseWeight,
                      selectedDayData,
                      recommendedList,
                      scientificTargets,
                      caloriesPerExercise,
                      selectedDayIndex == safeTodayIndex,
                      selectedDayDate,
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  // Widget xây dựng danh sách bài tập động dựa trên goal
  Widget _buildExercisesSliverList(
    bool isLoseWeight,
    Map<String, dynamic> selectedDayData,
    List<Map<String, dynamic>> recommendedList,
    Map<ExerciseType, int> scientificTargets,
    double caloriesPerExercise,
    bool allowWorkoutAction,
    DateTime selectedDayDate,
  ) {
    if (isLoseWeight) {
      if (selectedDayData['isRest'] == true) {
        return SliverToBoxAdapter(
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: AppTheme.glassDecoration(
              color: AppTheme.neonBlue.withValues(alpha: 0.1),
              borderRadius: 20,
            ),
            child: Column(
              children: [
                const Icon(Icons.spa, color: AppTheme.neonBlue, size: 40),
                const SizedBox(height: 12),
                const Text(
                  'NGÀY NGHỈ NGƠI & PHỤC HỒI',
                  style: TextStyle(
                    color: AppTheme.neonBlue,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  selectedDayData['reason'].toString(),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.8),
                    fontSize: 12,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        );
      }

      final List<dynamic> dayExercises =
          selectedDayData['exercises'] as List<dynamic>;
      return SliverList(
        delegate: SliverChildBuilderDelegate((context, index) {
          final rec = dayExercises[index] as Map<String, dynamic>;
          return _buildExerciseCard(
            rec,
            scientificTargets,
            caloriesPerExercise,
            allowWorkoutAction,
            selectedDayDate,
          );
        }, childCount: dayExercises.length),
      );
    } else {
      return SliverList(
        delegate: SliverChildBuilderDelegate((context, index) {
          final rec = recommendedList[index];
          return _buildExerciseCard(
            rec,
            scientificTargets,
            caloriesPerExercise,
            allowWorkoutAction,
            selectedDayDate,
          );
        }, childCount: recommendedList.length),
      );
    }
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
                child: Text(
                  allowWorkoutAction
                      ? (isCompletedForDay
                            ? 'Đã hoàn thành'
                            : 'Chưa hoàn thành')
                      : 'Chỉ xem lịch cho ngày này',
                  style: TextStyle(
                    color: allowWorkoutAction
                        ? (isCompletedForDay
                              ? AppTheme.neonGreen
                              : Colors.white70)
                        : Colors.white.withValues(alpha: 0.6),
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
                          // Thực hiện cập nhật trạng thái UI cục bộ (nếu cần offline)
                          _toggleExerciseCompletedForDay(
                            type,
                            selectedDayDate,
                            finalTargetCount,
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

  Widget _buildGoalChip(String goalKey, String label) {
    final isSelected = _selectedGoal == goalKey;
    return GestureDetector(
      onTap: () => _updateGoal(goalKey),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: isSelected
            ? AppTheme.glassDecoration(
                color: AppTheme.neonGreen.withValues(alpha: 0.2),
                borderRadius: 12,
              ).copyWith(
                border: Border.all(color: AppTheme.neonGreen, width: 1.5),
              )
            : AppTheme.glassDecoration(
                color: Colors.white.withValues(alpha: 0.04),
                borderRadius: 12,
              ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              color: isSelected ? AppTheme.neonGreen : Colors.white70,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              fontSize: 13,
            ),
          ),
        ),
      ),
    );
  }
}
