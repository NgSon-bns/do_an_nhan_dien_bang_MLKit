import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'dart:async';

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
  List<String> _heavyExercises = [];

  // Mảng lưu lịch trình 21 ngày đồng bộ từ Database
  List<Map<String, dynamic>> _savedSchedule = [];
  bool _showExerciseGroups = false; // Ẩn/Hiện chọn nhóm bài tập

  final Set<ExerciseType> _customSelectedExercises = {};
  bool _isCustomSelectionActive = false;
  final Set<ExerciseType> _tooHeavyExercises = {};
  List<String> _customMuscleGroupLoopHistory = [];
  Timer? _syncTimer;


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

  // Tiêu đề hiển thị cho từng nhóm bài tập khi lịch trình được sinh tự động
  static const Map<String, String> _groupWorkoutTitles = {
    'Thân trên': 'Kích hoạt bụng & Sức mạnh thân trên',
    'Thân dưới': 'Săn chắc chân mông & Đùi',
    'Toàn thân': 'Sức bền & Đốt mỡ toàn thân',
  };

  @override
  void initState() {
    super.initState();
    _selectedWeekIndex = 1;
    _selectedDayIndex = 7 + (DateTime.now().weekday - 1);
    _loadInitialData();
  }

  Future<void> _loadInitialData() async {
    // 1. Khởi động Timer đồng bộ định kỳ ngay lập tức để không bị chặn bởi các cuộc gọi mạng
    _syncTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      _syncPendingData();
    });

    // 2. Tải các dữ liệu cục bộ nhanh/offline
    final selectedDate = _getSelectedDayDate(_selectedDayIndex);
    _loadCompletedExercisesForDay(selectedDate);
    _loadMealLogsForDay(selectedDate);
    _refreshTodayDraftWorkout();

    final yesterday = selectedDate.subtract(const Duration(days: 1));
    _loadCompletedExercisesForDay(yesterday);

    // 3. Gọi các hàm tải/đồng bộ mạng dưới nền (non-blocking)
    _loadUserProfile().then((_) {
      _loadHeavyExercises();
      _loadAndSyncSchedule();
    }).catchError((e) {
      print('[_loadInitialData] Lỗi tải profile nền: $e');
    });
  }

  @override
  void dispose() {
    _syncTimer?.cancel();
    super.dispose();
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

    // 2. Fetch từ Supabase (nếu online và không có thay đổi offline chưa đồng bộ)
    if (_isSupabaseInitialized && user?.id != 'guest') {
      final isPending = await _isScheduleSyncPending();
      if (!isPending) {
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
      } else {
        // Cố gắng đồng bộ lên DB ngay khi mạng kết nối lại
        _syncPendingData();
      }
    }

    double bmi = _height > 0
        ? _weight / ((_height / 100) * (_height / 100))
        : 0.0;

    // 3. Căn chỉnh lịch trình với ngày tuần hiện tại (mới nhất) hoặc tạo mới hoàn toàn
    if (hasLocal && tempSchedule.isNotEmpty) {
      tempSchedule = _alignScheduleWithCurrentDates(tempSchedule, _selectedGoal, bmi, _age);
      await _saveScheduleLocallyAndDb(tempSchedule);
    } else {
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

  // Căn chỉnh/Trộn lịch trình cũ từ cache với các mốc ngày mới của 3 tuần hiển thị
  List<Map<String, dynamic>> _alignScheduleWithCurrentDates(
    List<Map<String, dynamic>> cachedSchedule,
    String goal,
    double bmi,
    int age,
  ) {
    final List<Map<String, dynamic>> aligned = [];
    const weekLabels = ['Tuần trước', 'Tuần này', 'Tuần sau'];

    // Đưa toàn bộ các ngày đã lưu vào map dạng key = date
    final Map<String, Map<String, dynamic>> cacheMap = {};
    for (var day in cachedSchedule) {
      final String? date = day['date'] as String?;
      if (date != null) {
        cacheMap[date] = day;
      }
    }

    for (int weekIndex = 0; weekIndex < 3; weekIndex++) {
      final DateTime selectedWeekMonday = _getSelectedDayDate(weekIndex * 7);
      
      final DateTime epoch = DateTime(2026, 1, 5);
      final DateTime mondayUtc = DateTime.utc(selectedWeekMonday.year, selectedWeekMonday.month, selectedWeekMonday.day);
      final DateTime epochUtc = DateTime.utc(epoch.year, epoch.month, epoch.day);
      final int diffDays = mondayUtc.difference(epochUtc).inDays;
      final int stableWeekIndex = diffDays ~/ 7;

      final fullBodyCount = _weeklyFullBodyCount(goal, stableWeekIndex);
      final pattern = _groupPatternForWeek(fullBodyCount);
      int slot = 0;

      for (int dayInWeek = 1; dayInWeek <= 7; dayInWeek++) {
        final int globalDay = weekIndex * 7 + dayInWeek;
        final DateTime dayDate = _getSelectedDayDate(globalDay - 1);
        final String dateStr = '${dayDate.year}-${dayDate.month.toString().padLeft(2, '0')}-${dayDate.day.toString().padLeft(2, '0')}';

        if (cacheMap.containsKey(dateStr)) {
          // Ngày này đã tồn tại trong lịch trình cũ -> giữ nguyên bài tập/custom và đồng bộ lại index
          final cachedDay = Map<String, dynamic>.from(cacheMap[dateStr]!);
          cachedDay['day'] = globalDay;
          cachedDay['weekLabel'] = weekLabels[weekIndex];
          aligned.add(cachedDay);
          
          if (dayInWeek != 3 && dayInWeek != 7) {
            slot++; // Giữ đồng bộ chỉ số slot xoay vòng
          }
        } else {
          // Chưa có -> sinh bài tập mới cho ngày đó theo thuật toán xoay vòng ổn định
          Map<String, dynamic> dayData;
          if (dayInWeek == 3) {
            dayData = _buildRestDay(isEndOfWeek: false);
          } else if (dayInWeek == 7) {
            dayData = _buildRestDay(isEndOfWeek: true);
          } else {
            final groupName = pattern[slot % pattern.length];
            slot++;
            dayData = _buildWorkoutDayFromGroup(groupName);
          }

          dayData['day'] = globalDay;
          dayData['weekLabel'] = weekLabels[weekIndex];
          dayData['date'] = dateStr;
          aligned.add(dayData);
        }
      }
    }

    return aligned;
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
      await _setScheduleSyncPending(false);
    } catch (e) {
      debugPrint('Mất mạng, chưa đồng bộ lên Database được: $e');
      await _setScheduleSyncPending(true);
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

    // Ép kiểu an toàn: dữ liệu cũ có thể lưu 'type' dạng String (trước khi
    // decode) hoặc ExerciseType, tránh crash làm dừng cả tiến trình lưu lịch.
    ExerciseType? _safeType(dynamic exMap) {
      if (exMap is! Map) return null;
      final raw = exMap['type'];
      if (raw is ExerciseType) return raw;
      if (raw is String) return _exerciseTypeFromName(raw);
      return null;
    }

    final prevExercises = <ExerciseType>{};
    for (final e in (previousDay['exercises'] as List?) ?? const []) {
      final t = _safeType(e);
      if (t != null) prevExercises.add(t);
    }

    final currExercises = (currentDay['exercises'] as List?) ?? [];
    List<Map<String, dynamic>> filteredExercises = [];

    for (var ex in currExercises) {
      final ExerciseType? type = _safeType(ex);
      if (type == null) {
        filteredExercises.add(Map<String, dynamic>.from(ex as Map));
        continue;
      }
      // Nếu bài tập trùng với ngày hôm trước, tự động đổi sang bài thay thế an toàn
      if (prevExercises.contains(type)) {
        final alternativeType = _getAlternativeExercise(type);
        filteredExercises.add({
          'type': alternativeType,
          'reason': 'Đổi bài để tránh trùng lặp liên tiếp với ngày hôm trước.',
        });
      } else {
        filteredExercises.add(Map<String, dynamic>.from(ex as Map));
      }
    }

    final updatedDay = Map<String, dynamic>.from(currentDay);
    updatedDay['exercises'] = filteredExercises;
    return updatedDay;
  }

  ExerciseType _getAlternativeExercise(ExerciseType type) {
    switch (type) {
      case ExerciseType.burpee:
        return ExerciseType.plank;
      case ExerciseType.push_up:
        return ExerciseType.squat;
      case ExerciseType.walking_lunge:
        return ExerciseType.burpee;
      case ExerciseType.squat:
        return ExerciseType.jumping_jack;
      case ExerciseType.jumping_jack:
        return ExerciseType.push_up;
      case ExerciseType.plank:
        return ExerciseType.walking_lunge;
    }
  }

  String _heavyExercisesPrefsKey() {
    final userId = _isSupabaseInitialized
        ? Supabase.instance.client.auth.currentUser?.id
        : null;
    return 'heavy_exercises_${userId ?? 'guest'}';
  }

  Future<void> _loadHeavyExercises() async {
    if (!_isSupabaseInitialized) {
      await _loadHeavyExercisesFromPrefs();
      return;
    }
    try {
      final client = Supabase.instance.client;
      final userId = client.auth.currentUser?.id;
      if (userId == null) {
        await _loadHeavyExercisesFromPrefs();
        return;
      }
      final row = await client
          .from('ho_so_nguoi_dung')
          .select('bai_tap_qua_nang')
          .eq('ma_nguoi_dung', userId)
          .maybeSingle();

      final list =
          (row?['bai_tap_qua_nang'] as List?)
              ?.map((e) => e.toString())
              .toList() ??
          [];

      if (mounted) {
        setState(() {
          _heavyExercises = list;
        });
      }
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_heavyExercisesPrefsKey(), list);
    } catch (e) {
      debugPrint('Lỗi tải bài tập quá nặng từ CSDL: $e');
      await _loadHeavyExercisesFromPrefs();
    }
  }

  Future<void> _loadHeavyExercisesFromPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = prefs.getStringList(_heavyExercisesPrefsKey()) ?? [];
      if (mounted) {
        setState(() {
          _heavyExercises = list;
        });
      }
    } catch (e) {
      debugPrint('Lỗi tải bài tập quá nặng: $e');
    }
  }

  Future<void> _removeHeavyExercise(ExerciseType type) async {
    final updated = List<String>.from(_heavyExercises)..remove(type.name);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_heavyExercisesPrefsKey(), updated);

      if (mounted) {
        setState(() {
          _heavyExercises = updated;
        });
      }

      if (_isSupabaseInitialized) {
        final client = Supabase.instance.client;
        final userId = client.auth.currentUser?.id;
        if (userId != null) {
          await client
              .from('ho_so_nguoi_dung')
              .update({'bai_tap_qua_nang': updated})
              .eq('ma_nguoi_dung', userId);
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Đã bỏ chặn bài tập này'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      debugPrint('Lỗi xóa bài tập quá nặng: $e');
    }
  }

  bool _isExerciseBlocked(ExerciseType type, double bmi, int age) {
    if (type == ExerciseType.burpee && (bmi >= 25.0 || age >= 45)) return true;
    if (_heavyExercises.contains(type.name)) return true;
    return false;
  }

  String _getBlockedReason(ExerciseType type, double bmi, int age) {
    if (type == ExerciseType.burpee) {
      if (bmi >= 25.0) {
        return '⚠️ Bị chặn: Thừa cân (BMI ≥ 25), Burpee gây áp lực lớn lên khớp gối';
      }
      if (age >= 45) {
        return '⚠️ Bị chặn: Cao tuổi (≥ 45), Burpee cường độ cao có thể gây ngã nguy hiểm';
      }
    }
    if (_heavyExercises.contains(type.name)) {
      return '⚠️ Bị chặn: AI phát hiện bài này quá nặng với bạn';
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

  Future<void> _saveProfileLocally(Map<String, dynamic> profile) async {
    final prefs = await SharedPreferences.getInstance();
    final user = _client.auth.currentUser;
    final key = 'cached_profile_${user?.id ?? 'guest'}';
    await prefs.setString(key, jsonEncode(profile));
  }

  Future<Map<String, dynamic>?> _loadProfileLocally() async {
    final prefs = await SharedPreferences.getInstance();
    final user = _client.auth.currentUser;
    final key = 'cached_profile_${user?.id ?? 'guest'}';
    final data = prefs.getString(key);
    if (data != null && data.isNotEmpty) {
      try {
        return jsonDecode(data) as Map<String, dynamic>;
      } catch (e) {
        debugPrint('Lỗi giải mã profile local: $e');
      }
    }
    return null;
  }

  Future<void> _setProfileSyncPending(bool pending) async {
    final prefs = await SharedPreferences.getInstance();
    final user = _client.auth.currentUser;
    final key = 'profile_sync_pending_${user?.id ?? 'guest'}';
    await prefs.setBool(key, pending);
  }

  Future<bool> _isProfileSyncPending() async {
    final prefs = await SharedPreferences.getInstance();
    final user = _client.auth.currentUser;
    final key = 'profile_sync_pending_${user?.id ?? 'guest'}';
    return prefs.getBool(key) ?? false;
  }

  Future<void> _setScheduleSyncPending(bool pending) async {
    final prefs = await SharedPreferences.getInstance();
    final user = _client.auth.currentUser;
    final key = 'schedule_sync_pending_${user?.id ?? 'guest'}';
    await prefs.setBool(key, pending);
  }

  Future<bool> _isScheduleSyncPending() async {
    final prefs = await SharedPreferences.getInstance();
    final user = _client.auth.currentUser;
    final key = 'schedule_sync_pending_${user?.id ?? 'guest'}';
    return prefs.getBool(key) ?? false;
  }

  Future<void> _syncPendingData() async {
    print('[syncPendingData] Đang kiểm tra trạng thái mạng và tài khoản...');
    if (!_isSupabaseInitialized) {
      print('[syncPendingData] Lỗi: Chưa khởi tạo Supabase');
      return;
    }
    final user = _client.auth.currentUser;
    if (user == null || user.id == 'guest') {
      print('[syncPendingData] User chưa đăng nhập hoặc là Guest. Bỏ qua đồng bộ.');
      return;
    }

    // Cập nhật số lượng bài tập chưa sync cục bộ
    try {
      final prefs = await SharedPreferences.getInstance();
      final data = prefs.getString('cached_completed_workouts_${user.id}');
      int pendingCount = 0;
      if (data != null && data.isNotEmpty) {
        final List decoded = jsonDecode(data) as List;
        pendingCount = decoded.where((item) => item['is_synced'] == false).length;
      }
      print('[syncPendingData] Số bài tập chưa đồng bộ: $pendingCount');
    } catch (e) {
      print('[syncPendingData] Lỗi đếm số bài tập chưa sync: $e');
    }

    // 1. Đồng bộ profile nếu cần
    if (await _isProfileSyncPending()) {
      final local = await _loadProfileLocally();
      if (local != null) {
        try {
          final client = Supabase.instance.client;
          await client
              .from('ho_so_nguoi_dung')
              .update({
                'chieu_cao': local['chieu_cao'],
                'can_nang': local['can_nang'],
                'tuoi': local['tuoi'],
                'gioi_tinh': local['gioi_tinh'],
                'muc_tieu': local['muc_tieu'],
              })
              .eq('ma_nguoi_dung', user.id);
          await _setProfileSyncPending(false);
          print('[syncPendingData] Đã tự động đồng bộ Profile lên Database thành công!');
        } catch (e) {
          print('[syncPendingData] Đồng bộ Profile thất bại (tiếp tục chờ online): $e');
        }
      }
    }

    // 2. Đồng bộ lịch trình nếu cần
    if (await _isScheduleSyncPending()) {
      if (_savedSchedule.isNotEmpty) {
        try {
          final client = Supabase.instance.client;
          await client.from('lich_trinh_de_xuat').upsert({
            'ma_nguoi_dung': user.id,
            'ngay_cap_nhat': DateTime.now().toIso8601String(),
            'du_lieu_lich_trinh': _encodeSchedule(_savedSchedule),
          }, onConflict: 'ma_nguoi_dung');
          await _setScheduleSyncPending(false);
          print('[syncPendingData] Đã tự động đồng bộ Lịch trình lên Database thành công!');
        } catch (e) {
          print('[syncPendingData] Đồng bộ Lịch trình thất bại (tiếp tục chờ online): $e');
        }
      }
    }
    // 3. Đồng bộ lịch sử tập luyện hoàn thành (lich_su_tap_luyen) nếu có các buổi tập offline chưa đồng bộ
    try {
      final bool didSync = await DatabaseService().syncPendingWorkouts();

      if (didSync) {
        // Tải lại lịch sử tập của hôm nay và hôm qua để cập nhật giao diện
        final selectedDate = _getSelectedDayDate(_selectedDayIndex);
        await _loadCompletedExercisesForDay(selectedDate);
        final yesterday = selectedDate.subtract(const Duration(days: 1));
        await _loadCompletedExercisesForDay(yesterday);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Đã tự động đồng bộ kết quả tập luyện offline thành công!'),
              backgroundColor: AppTheme.neonGreen,
              duration: Duration(seconds: 2),
            ),
          );
        }
      }
    } catch (e) {
      print('[syncPendingData] Đồng bộ lịch sử tập offline thất bại: $e');
    }
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
    final exercises = _exerciseGroups[groupName] ?? [];
    final validExercises = exercises
        .where((e) => _isExerciseSelectableForDay(e, selectedDayDate, bmi, age))
        .toList();
    if (validExercises.isEmpty) return;

    if (_hasStartedTodayWorkout()) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Bạn đã bắt đầu tập luyện ngày hôm nay. Không thể thay đổi bài tập!',
            ),
            backgroundColor: AppTheme.errorRed,
          ),
        );
      }
      return;
    }

    setState(() {
      _isCustomSelectionActive = true;
      final allSelected = validExercises.every(
        (e) => _customSelectedExercises.contains(e),
      );
      if (allSelected) {
        for (final e in validExercises) {
          _customSelectedExercises.remove(e);
        }
        if (_customSelectedExercises.isEmpty) {
          _isCustomSelectionActive = false;
        }
      } else {
        for (final e in validExercises) {
          _customSelectedExercises.add(e);
        }
      }
    });

    if (_savedSchedule.isNotEmpty) {
      try {
        final String targetDateStr = '${selectedDayDate.year}-${selectedDayDate.month.toString().padLeft(2, '0')}-${selectedDayDate.day.toString().padLeft(2, '0')}';
        final int targetIndex = _savedSchedule.indexWhere((day) => day['date'] == targetDateStr);
        if (targetIndex == -1) {
          print('[_toggleExerciseGroup] Không tìm thấy ngày tương ứng trong lịch trình: $targetDateStr');
          return;
        }

        final scientificTargets = _calculateScientificReps(
          _weight,
          _height,
          _age,
          _selectedGoal,
          _gender,
        );
        final customList = _buildCustomExerciseList(scientificTargets);

        List<Map<String, dynamic>> updatedSchedule = List.from(_savedSchedule);
        updatedSchedule[targetIndex] = Map<String, dynamic>.from(
          updatedSchedule[targetIndex],
        );
        updatedSchedule[targetIndex]['exercises'] = customList;
        updatedSchedule[targetIndex]['isRest'] = false;

        // Cập nhật cascade từ ngày đó trở đi
        for (int i = targetIndex + 1; i < updatedSchedule.length; i++) {
          updatedSchedule[i] = _ensureNoConsecutiveDuplicate(
            updatedSchedule[i],
            updatedSchedule[i - 1],
          );
        }

        print(
          'Đã cập nhật lịch ngày $targetDateStr (index $targetIndex) và cascade '
          'tới ${updatedSchedule.length - 1 - targetIndex} ngày sau đó.',
        );

        await _saveScheduleLocallyAndDb(updatedSchedule);
      } catch (e, st) {
        debugPrint('Lỗi khi cập nhật lịch trình theo nhóm bài tập: $e\n$st');
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
        GestureDetector(
          onTap: () {
            setState(() {
              _showExerciseGroups = !_showExerciseGroups;
            });
          },
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
            color: Colors.transparent,
            child: Row(
              children: [
                const Icon(
                  Icons.touch_app,
                  color: AppTheme.neonGreen,
                  size: 16,
                ),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'CHỌN NHÓM BÀI TẬP (ẨN/HIỆN)',
                    style: TextStyle(
                      color: AppTheme.neonGreen,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
                Icon(
                  _showExerciseGroups
                      ? Icons.keyboard_arrow_up
                      : Icons.keyboard_arrow_down,
                  color: AppTheme.neonGreen,
                  size: 20,
                ),
              ],
            ),
          ),
        ),
        if (_hasStartedTodayWorkout()) ...[
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
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
                    'Bạn đã bắt đầu tập luyện hôm nay. Các nhóm bài tập được khóa cố định.',
                    style: TextStyle(
                      color: AppTheme.errorRed.withValues(alpha: 0.9),
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
        if (_showExerciseGroups) ...[
          const SizedBox(height: 8),
          ..._exerciseGroups.entries.map((entry) {
            final groupName = entry.key;
            final exercises = entry.value;
            final availableExercises = exercises
                .where(
                  (e) =>
                      _isExerciseSelectableForDay(e, selectedDayDate, bmi, age),
                )
                .toList();
            final blockedExercises = exercises
                .where((e) => _isExerciseBlocked(e, bmi, age))
                .toList();
            final repeatedExercises = exercises
                .where(
                  (e) => _isExerciseDoneOnDate(
                    e,
                    selectedDayDate.subtract(const Duration(days: 1)),
                  ),
                )
                .toList();
            final allSelected = availableExercises.every(
              (e) => _customSelectedExercises.contains(e),
            );
            final hasWarnings =
                blockedExercises.isNotEmpty || repeatedExercises.isNotEmpty;

            return Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: hasWarnings
                    ? Colors.red.withValues(alpha: 0.06)
                    : Colors.white.withValues(alpha: 0.04),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: hasWarnings
                      ? AppTheme.errorRed.withValues(alpha: 0.35)
                      : Colors.white10,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              groupName,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _groupReasons[groupName] ?? '',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.7),
                                fontSize: 11.5,
                                height: 1.3,
                              ),
                            ),
                          ],
                        ),
                      ),
                      TextButton(
                        onPressed: (availableExercises.isEmpty || _hasStartedTodayWorkout())
                            ? null
                            : () => _toggleExerciseGroup(
                                groupName,
                                bmi,
                                age,
                                selectedDayDate,
                              ),
                        style: TextButton.styleFrom(
                          foregroundColor: allSelected
                              ? AppTheme.neonGreen
                              : AppTheme.neonBlue,
                        ),
                        child: Text(
                          allSelected ? 'BỎ CHỌN' : 'CHỌN NHÓM',
                          style: const TextStyle(fontSize: 11.5),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: exercises.map((exerciseType) {
                      final isBlocked = _isExerciseBlocked(
                        exerciseType,
                        bmi,
                        age,
                      );
                      final isRepeated = _isExerciseDoneOnDate(
                        exerciseType,
                        selectedDayDate.subtract(const Duration(days: 1)),
                      );
                      final isSelectable = !isBlocked && !isRepeated;
                      final isSelected = _customSelectedExercises.contains(
                        exerciseType,
                      );
                      final exerciseLabel = ExerciseDetail.defaultExercises
                          .firstWhere((e) => e.type == exerciseType)
                          .name;

                      return Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: isBlocked
                              ? AppTheme.errorRed.withValues(alpha: 0.12)
                              : isSelected
                              ? AppTheme.neonGreen.withValues(alpha: 0.12)
                              : Colors.white.withValues(alpha: 0.04),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: isBlocked
                                ? AppTheme.errorRed.withValues(alpha: 0.45)
                                : isSelected
                                ? AppTheme.neonGreen.withValues(alpha: 0.45)
                                : Colors.white10,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              exerciseLabel,
                              style: TextStyle(
                                color: isBlocked
                                    ? AppTheme.errorRed
                                    : Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 11.5,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              isBlocked
                                  ? _getBlockedReason(exerciseType, bmi, age)
                                  : isRepeated
                                  ? 'Đã tập hôm trước'
                                  : isSelectable
                                  ? 'Có thể chọn'
                                  : 'Không khả dụng',
                              style: TextStyle(
                                color: isBlocked
                                    ? AppTheme.errorRed
                                    : Colors.white70,
                                fontSize: 10.5,
                                height: 1.3,
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
            );
          }).toList(),
        ],
      ],
    );
  }

  ExerciseType _getAdaptedExerciseType(ExerciseType type) {
    ExerciseType current = type;
    while (_heavyExercises.contains(current.name)) {
      if (current == ExerciseType.burpee) {
        current = ExerciseType.jumping_jack;
      } else if (current == ExerciseType.push_up) {
        current = ExerciseType.plank;
      } else if (current == ExerciseType.walking_lunge) {
        current = ExerciseType.squat;
      } else if (current == ExerciseType.squat) {
        current = ExerciseType.jumping_jack;
      } else if (current == ExerciseType.jumping_jack) {
        current = ExerciseType.plank;
      } else {
        break;
      }
    }
    return current;
  }

  String _getAdaptedReason(
    ExerciseType originalType,
    ExerciseType adaptedType,
    String originalReason,
  ) {
    if (originalType == adaptedType) return originalReason;
    final adaptedEx = ExerciseDetail.defaultExercises.firstWhere(
      (e) => e.type == adaptedType,
    );
    final originalEx = ExerciseDetail.defaultExercises.firstWhere(
      (e) => e.type == originalType,
    );
    return 'Bài tập thay thế: Bạn tập ${originalEx.name} chưa quen nên HLV tự động chuyển sang ${adaptedEx.name} nhẹ hơn để bảo vệ cơ thể.';
  }

  List<Map<String, dynamic>> _postProcessAdaptiveSchedule(
    List<Map<String, dynamic>> rawSchedule,
  ) {
    // rawSchedule đã là danh sách đầy đủ 21 ngày (3 tuần) do
    // _generateAdaptiveSchedule sinh ra tự động, không cần nhân bản nữa.
    final List<Map<String, dynamic>> processed = [];
    for (int index = 0; index < rawSchedule.length; index++) {
      final day = rawSchedule[index];
      final dayCopy = Map<String, dynamic>.from(day);
      if (dayCopy['isRest'] == true) {
        processed.add(dayCopy);
        continue;
      }
      final List<dynamic> exercises = List.from(dayCopy['exercises'] as List);
      final List<Map<String, dynamic>> newExercises = [];
      for (int i = 0; i < exercises.length; i++) {
        final exMap = Map<String, dynamic>.from(exercises[i] as Map);
        ExerciseType originalType = exMap['type'] as ExerciseType;
        ExerciseType adaptedType = _getAdaptedExerciseType(originalType);

        // Kiểm tra không trùng bài với ngày trước đó
        if (index > 0 && processed[index - 1]['isRest'] != true) {
          final prevExercises =
              (processed[index - 1]['exercises'] as List?)
                  ?.map((e) => e['type'] as ExerciseType)
                  .toSet() ??
              {};
          if (prevExercises.contains(adaptedType)) {
            adaptedType = _getAlternativeExercise(adaptedType);
          }
        }

        if (originalType != adaptedType) {
          exMap['type'] = adaptedType;
          exMap['reason'] = _getAdaptedReason(
            originalType,
            adaptedType,
            exMap['reason'] as String,
          );
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
    // 1. Tải Profile từ Local Cache trước để giao diện hiện lập tức (Offline-first)
    final localProfile = await _loadProfileLocally();
    if (localProfile != null) {
      if (mounted) {
        setState(() {
          _userName = localProfile['ho_ten'] ?? 'Trainer';
          _weight = (localProfile['can_nang'] as num?)?.toDouble() ?? 65.0;
          _height = (localProfile['chieu_cao'] as num?)?.toDouble() ?? 170.0;
          _age = (localProfile['tuoi'] as num?)?.toInt() ?? 25;
          _gender = localProfile['gioi_tinh'] ?? 'male';
          _selectedGoal = localProfile['muc_tieu'] ?? 'maintain';
          _isLoading = false;
        });
      }
    }

    if (!_isSupabaseInitialized) {
      if (localProfile == null) {
        setState(() {
          _weight = 65.0;
          _height = 170.0;
          _age = 25;
          _userName = 'Khách (Offline)';
          _isLoading = false;
        });
      }
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final profile = await _authService.getCurrentUserProfile();
      if (profile != null && mounted) {
        // Chỉ cập nhật từ DB nếu không có chỉnh sửa offline đang chờ đồng bộ
        if (!(await _isProfileSyncPending())) {
          setState(() {
            _userName = profile['ho_ten'] ?? 'Trainer';
            _weight = (profile['can_nang'] as num?)?.toDouble() ?? 65.0;
            _height = (profile['chieu_cao'] as num?)?.toDouble() ?? 170.0;
            _age = (profile['tuoi'] as num?)?.toInt() ?? 25;
            _gender = profile['gioi_tinh'] ?? 'male';

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

          // Lưu cache mới nhất
          await _saveProfileLocally({
            'ho_ten': _userName,
            'can_nang': _weight,
            'chieu_cao': _height,
            'tuoi': _age,
            'gioi_tinh': _gender,
            'muc_tieu': _selectedGoal,
          });
        }
      }
    } catch (e) {
      debugPrint('Lỗi tải hồ sơ đề xuất từ Cloud (Dùng local cache): $e');
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
      // Thử tự động đồng bộ dữ liệu ngoại tuyến nếu có mạng lại
      _syncPendingData();
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

    // 1. Cập nhật State cục bộ lập tức
    setState(() {
      _height = newHeight;
      _weight = newWeight;
      _age = newAge;
      _gender = newGender;
    });

    // 2. Lưu vào Cache cục bộ lập tức
    final localProfile = {
      'chieu_cao': newHeight,
      'can_nang': newWeight,
      'tuoi': newAge,
      'gioi_tinh': newGender,
      'muc_tieu': nextGoal,
      'ho_ten': _userName,
    };
    await _saveProfileLocally(localProfile);

    // 3. Cập nhật lịch trình cục bộ lập tức
    if (nextGoal != _selectedGoal) {
      await _updateGoal(nextGoal, currentBmi: newBmi);
    } else {
      await _triggerScheduleUpdateFromToday(newBmi);
    }

    // 4. Đồng bộ lên Supabase
    bool syncSuccess = false;
    if (_isSupabaseInitialized) {
      final client = Supabase.instance.client;
      final userId = client.auth.currentUser?.id;
      if (userId != null) {
        try {
          await client
              .from('ho_so_nguoi_dung')
              .update({
                'chieu_cao': newHeight,
                'can_nang': newWeight,
                'tuoi': newAge,
                'gioi_tinh': newGender,
              })
              .eq('ma_nguoi_dung', userId);
          syncSuccess = true;
          await _setProfileSyncPending(false);
        } catch (e) {
          debugPrint('Lỗi đồng bộ hồ sơ thể chất (Sẽ lưu offline): $e');
          await _setProfileSyncPending(true);
        }
      }
    }

    setState(() {
      _isLoading = false;
    });

    if (mounted) {
      if (syncSuccess) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Đã cập nhật chỉ số thể chất thành công!'),
            backgroundColor: AppTheme.neonGreen,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Mất mạng. Đã lưu ngoại tuyến, tự động đồng bộ khi có Internet!'),
            backgroundColor: Colors.orangeAccent,
          ),
        );
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

    // Lưu cục bộ mục tiêu mới
    final currentLocal = await _loadProfileLocally() ?? {};
    currentLocal['muc_tieu'] = newGoal;
    await _saveProfileLocally(currentLocal);

    if (_isSupabaseInitialized) {
      final client = Supabase.instance.client;
      final userId = client.auth.currentUser?.id;
      if (userId != null) {
        try {
          await client
              .from('ho_so_nguoi_dung')
              .update({'muc_tieu': newGoal})
              .eq('ma_nguoi_dung', userId);
          await _setProfileSyncPending(false);
        } catch (e) {
          debugPrint('Lỗi đồng bộ mục tiêu (Sẽ lưu offline): $e');
          await _setProfileSyncPending(true);
        }
      }
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
      if (ex is! Map) continue;
      final rawType = ex['type'];
      ExerciseType? type;
      if (rawType is ExerciseType) {
        type = rawType;
      } else if (rawType is String) {
        type = _exerciseTypeFromName(rawType);
      }
      if (type != null && _isExerciseCompletedForDay(type, selectedDate)) {
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
        final String? maBaiTapRieng =
            row['ma_bai_tap_rieng'] as String? ?? row['exercise_id'] as String?;
        final int soLanTap =
            (row['so_lan_tap'] as num?)?.toInt() ??
            (row['reps_count'] as num?)?.toInt() ??
            0;

        String exerciseName = maBaiTapRieng ?? '';

        if (exerciseName.isNotEmpty && soLanTap > 0) {
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
    String gender,
  ) {
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
    final double caloriesPerExercise = targetWorkoutCalories / 4;
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

  // Số buổi "Toàn thân" mỗi tuần theo mục tiêu:
  // - lose: 2 buổi/tuần | - maintain: 1 buổi/tuần | - build: 1 buổi / 2 tuần
  // weekIndex: 0 = Tuần trước, 1 = Tuần này, 2 = Tuần sau
  int _weeklyFullBodyCount(String goal, int weekIndex) {
    switch (goal) {
      case 'lose':
        return 2;
      case 'build':
        // 1 buổi mỗi 2 tuần -> so le giữa các tuần
        return weekIndex % 2 == 0 ? 1 : 0;
      case 'maintain':
      default:
        return 1;
    }
  }

  // Sắp xếp nhóm bài cho 5 ngày tập trong tuần (bỏ qua 2 ngày nghỉ),
  // đảm bảo 2 ngày tập liên tiếp không cùng nhóm bài tập.
  List<String> _groupPatternForWeek(int fullBodyCount) {
    switch (fullBodyCount) {
      case 2:
        return const [
          'Toàn thân',
          'Thân trên',
          'Thân dưới',
          'Toàn thân',
          'Thân trên',
        ];
      case 1:
        return const [
          'Thân trên',
          'Thân dưới',
          'Toàn thân',
          'Thân trên',
          'Thân dưới',
        ];
      case 0:
      default:
        return const [
          'Thân trên',
          'Thân dưới',
          'Thân trên',
          'Thân dưới',
          'Thân trên',
        ];
    }
  }

  Map<String, dynamic> _buildWorkoutDayFromGroup(String groupName) {
    final exercises = _exerciseGroups[groupName] ?? const [];
    return {
      'title': _groupWorkoutTitles[groupName] ?? groupName,
      'isRest': false,
      'exercises': exercises.map((type) {
        final ex = ExerciseDetail.defaultExercises.firstWhere(
          (e) => e.type == type,
        );
        return {
          'type': type,
          'reason': '${ex.name} - ${_groupReasons[groupName] ?? ''}',
        };
      }).toList(),
    };
  }

  Map<String, dynamic> _buildRestDay({required bool isEndOfWeek}) {
    return {
      'title': 'Nghỉ ngơi phục hồi',
      'isRest': true,
      'reason': isEndOfWeek
          ? 'Hoàn thành chu kỳ tuần tập luyện. Hãy uống đủ nước, ăn đủ chất và ngủ sâu để chuẩn bị cho chu kỳ tiếp theo hiệu quả hơn!'
          : 'Hãy thực hiện các động tác giãn cơ nhẹ nhàng hoặc đi bộ thư giãn để giải phóng axit lactic và giúp cơ bắp hồi phục.',
    };
  }

  // Tự động sinh lịch trình 21 ngày (3 tuần) dựa trên mục tiêu, thay cho
  // danh sách cố định trước đây. Ngày nghỉ giữ nguyên vị trí (ngày 3 và 7
  // mỗi tuần), các nhóm bài tập được xoay vòng để không trùng nhau giữa
  // 2 ngày tập liên tiếp.
  List<Map<String, dynamic>> _generateAdaptiveSchedule(
    String goal,
    double bmi,
    int age,
  ) {
    final List<Map<String, dynamic>> schedule = [];
    const weekLabels = ['Tuần trước', 'Tuần này', 'Tuần sau'];

    for (int weekIndex = 0; weekIndex < 3; weekIndex++) {
      // Tìm ngày thứ hai của tuần tương ứng
      final DateTime selectedWeekMonday = _getSelectedDayDate(weekIndex * 7);

      // Tính số tuần kể từ mốc cố định ngày 05/01/2026 (một ngày Thứ Hai) để làm stableWeekIndex
      final DateTime epoch = DateTime(2026, 1, 5);
      final DateTime mondayUtc = DateTime.utc(selectedWeekMonday.year, selectedWeekMonday.month, selectedWeekMonday.day);
      final DateTime epochUtc = DateTime.utc(epoch.year, epoch.month, epoch.day);
      final int diffDays = mondayUtc.difference(epochUtc).inDays;
      final int stableWeekIndex = diffDays ~/ 7;

      final fullBodyCount = _weeklyFullBodyCount(goal, stableWeekIndex);
      final pattern = _groupPatternForWeek(fullBodyCount);
      int slot = 0;

      for (int dayInWeek = 1; dayInWeek <= 7; dayInWeek++) {
        final int globalDay = weekIndex * 7 + dayInWeek;
        // Tính ngày thực tế tương ứng với ngày trong danh sách đề xuất
        final DateTime dayDate = _getSelectedDayDate(globalDay - 1);
        final String dateStr = '${dayDate.year}-${dayDate.month.toString().padLeft(2, '0')}-${dayDate.day.toString().padLeft(2, '0')}';

        Map<String, dynamic> dayData;

        if (dayInWeek == 3) {
          dayData = _buildRestDay(isEndOfWeek: false);
        } else if (dayInWeek == 7) {
          dayData = _buildRestDay(isEndOfWeek: true);
        } else {
          final groupName = pattern[slot % pattern.length];
          slot++;
          dayData = _buildWorkoutDayFromGroup(groupName);
        }

        dayData['day'] = globalDay;
        dayData['weekLabel'] = weekLabels[weekIndex];
        dayData['date'] = dateStr;
        schedule.add(dayData);
      }
    }

    return schedule;
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
                                                rec as Map<String, dynamic>,
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

                                  if (currentExercises.isEmpty) {
                                    if (isToday&&!isRest) {
                                      return _buildExerciseGroupSelector(
                                        bmi,
                                        _age,
                                        selectedDayDate,
                                      );
                                    }
                                    return const SizedBox.shrink();
                                  }

                                  int totalExercises = currentExercises.length;
                                  int completedCount = 0;
                                  final List<String> completedList = [];
                                  final List<String> missingList = [];

                                  for (var rec in currentExercises) {
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
                                      if (isToday&&!isRest) ...[
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
                                      ...currentExercises.map((rec) {
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
                  if (_heavyExercises.contains(type.name)) ...[
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: () => _removeHeavyExercise(type),
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: AppTheme.errorRed.withValues(alpha: 0.15),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.close,
                          color: AppTheme.errorRed,
                          size: 14,
                        ),
                      ),
                    ),
                  ],
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
                        await _loadHeavyExercises();
                        if ((result == true || result == 'complete') &&
                            mounted) {
                          _toggleExerciseCompletedForDay(
                            type,
                            selectedDayDate,
                            finalTargetCount,
                            isManual: false,
                          );
                          await _loadCompletedExercisesForDay(selectedDayDate);
                          await _syncPendingData();
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