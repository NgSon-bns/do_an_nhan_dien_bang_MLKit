import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:async';

import 'package:demo/core/theme/app_theme.dart';
import 'package:demo/domain/exercise.dart';
import 'package:demo/data/services/auth_service.dart';
import 'package:demo/data/services/database_service.dart';
import 'profile_screen.dart';
import 'recommendation_screen.dart';
import 'package:demo/data/services/check_in_service.dart';
import 'package:demo/data/services/workout_draft_service.dart';
import 'workout/workout_screen.dart';

import 'package:demo/presentation/widgets/workout_history_bottom_sheet.dart';

class ExerciseListScreen extends StatefulWidget {
  final List<CameraDescription> cameras;

  const ExerciseListScreen({super.key, required this.cameras});

  @override
  State<ExerciseListScreen> createState() => _ExerciseListScreenState();
}

class _ExerciseListScreenState extends State<ExerciseListScreen> {
  final AuthService _authService = AuthService();
  final DatabaseService _databaseService = DatabaseService();
  final Map<ExerciseType, int> _selectedTargets = {};
  final Map<ExerciseType, bool> _noSplitTargets = {};

  // Các chỉ số thống kê thực tế
  double _totalCalories = 0.0;
  int _totalMinutes = 0;
  String _userName = 'Trainer';
  bool _isLoadingStats = true;

  // Điểm danh hàng ngày
  final CheckInService _checkInService = CheckInService();
  final WorkoutDraftService _workoutDraftService = WorkoutDraftService();
  int _checkInStreak = 0;
  bool _hasCheckedInToday = false;
  List<Map<String, dynamic>> _weekCheckInStatus = [];
  bool _isLoadingCheckIn = true;
  Map<String, dynamic>? _todayDraftWorkout;

  // Danh sách bài tập lấy từ database tiếng Việt (mặc định fallback về local list)
  List<ExerciseDetail> _exercisesList = ExerciseDetail.defaultExercises;
  Timer? _syncTimer;

  @override
  void initState() {
    super.initState();
    _loadDashboardData();
    _loadCheckInData();
    _refreshTodayDraftWorkout();
    _loadExercisesFromDb();

    _syncTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      _syncPendingData();
    });
  }

  @override
  void dispose() {
    _syncTimer?.cancel();
    super.dispose();
  }

  Future<void> _clearTodayDraftWorkout() async {
    // Gọi service để xóa bài tập nháp dưới local/database
    // Bạn hãy thay thế tên hàm đúng với service của bạn (ví dụ: clearTodayDraftWorkout)
    await _workoutDraftService.clearTodayDraftWorkout();

    // Cập nhật lại UI sau khi xóa thành công
    await _refreshTodayDraftWorkout();
  }

  Future<void> _refreshTodayDraftWorkout() async {
    final draft = await _workoutDraftService.getTodayDraftWorkout();
    if (mounted) {
      setState(() {
        _todayDraftWorkout = draft;
      });
    }
  }

  Future<void> _loadCheckInData() async {
    await _refreshTodayDraftWorkout();
    setState(() {
      _isLoadingCheckIn = true;
    });
    try {
      await _checkInService.syncCheckInHistoryFromSupabase();
      final streak = await _checkInService.getStreak();
      final hasChecked = await _checkInService.hasCheckedInToday();
      final weekStatus = await _checkInService.getCurrentWeekCheckInStatus();
      if (mounted) {
        setState(() {
          _checkInStreak = streak;
          _hasCheckedInToday = hasChecked;
          _weekCheckInStatus = weekStatus;
          _isLoadingCheckIn = false;
        });
      }
    } catch (e) {
      debugPrint('Lỗi tải dữ liệu điểm danh: $e');
      if (mounted) {
        setState(() {
          _isLoadingCheckIn = false;
        });
      }
    }
  }

  void _showWorkoutHistory() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.cardBackground,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return WorkoutHistoryBottomSheet(databaseService: _databaseService);
      },
    );
  }

  Future<void> _handleCheckIn() async {
    if (_hasCheckedInToday) return;
    await _refreshTodayDraftWorkout();
    setState(() {
      _isLoadingCheckIn = true;
    });

    try {
      final result = await _checkInService.performCheckIn();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppTheme.neonGreen,
            duration: const Duration(seconds: 3),
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.black),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '${result['message']} (Chuỗi: ${result['streak']})',
                    style: const TextStyle(
                      color: Colors.black,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
        _loadCheckInData();
        _loadDashboardData();
      }
    } catch (e) {
      debugPrint('Lỗi thực hiện điểm danh: $e');
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

  Future<void> _loadDashboardData() async {
    if (!_isSupabaseInitialized) {
      setState(() {
        _isLoadingStats = false;
        _userName = 'Khách (Offline)';
      });
      return;
    }
    await _refreshTodayDraftWorkout();
    setState(() {
      _isLoadingStats = true;
    });

    try {
      // 1. Tải thông tin người dùng
      final profile = await _authService.getCurrentUserProfile();
      if (profile != null && mounted) {
        setState(() {
          _userName = profile['ho_ten'] ?? 'Trainer';
        });

        // Kiểm tra xem người dùng đã cập nhật đầy đủ chiều cao, cân nặng, độ tuổi chưa
        final double weight = (profile['can_nang'] as num?)?.toDouble() ?? 0.0;
        final double height = (profile['chieu_cao'] as num?)?.toDouble() ?? 0.0;
        final int age = (profile['tuoi'] as num?)?.toInt() ?? 0;
        final String gender = ((profile['gioi_tinh'] as String?) ?? '').trim().toLowerCase();
        final String normalizedGender = gender == 'female' ? 'female' : 'male';
        if (weight == 0.0 || height == 0.0 || age == 0 || gender.isEmpty) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _showPhysicalSurveyDialog(
              currentName: profile['ho_ten'] ?? '',
              currentWeight: weight,
              currentHeight: height,
              currentAge: age,
              currentGender: normalizedGender,
            );
          });
        }
      }

      // 2. Tải thống kê tập luyện từ CSDL
      final stats = await _databaseService.getWorkoutStats();
      if (mounted) {
        setState(() {
          _totalCalories = stats['totalCalories'] ?? 0.0;
          _totalMinutes = stats['totalMinutes'] ?? 0;
        });
      }
    } catch (e) {
      debugPrint('Lỗi tải dữ liệu Dashboard: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingStats = false;
        });
      }
    }
  }

  Future<void> _loadExercisesFromDb() async {
    if (!_isSupabaseInitialized) {
      return;
    }

    try {
      final dbData = await _databaseService.getExercisesFromDatabase();
      if (dbData.isNotEmpty && mounted) {
        final List<ExerciseDetail> updatedList = [];
        for (var row in dbData) {
          final String ma = row['ma_bai_tap'] as String;
          final localEx = ExerciseDetail.defaultExercises.firstWhere(
            (e) => e.type.name == ma,
            orElse: () => ExerciseDetail.defaultExercises.first,
          );

          // Lấy mảng danh sách từ database hoặc dự phòng cục bộ
          final List<String> listInstructions = [];
          if (row['huong_dan_tap'] is List) {
            listInstructions.addAll(
              (row['huong_dan_tap'] as List).map((e) => e.toString()),
            );
          } else {
            listInstructions.addAll(localEx.instructions);
          }

          final List<String> listBenefits = [];
          if (row['loi_ich'] is List) {
            listBenefits.addAll(
              (row['loi_ich'] as List).map((e) => e.toString()),
            );
          } else {
            listBenefits.addAll(localEx.benefits);
          }

          updatedList.add(
            ExerciseDetail(
              type: localEx.type,
              name: (row['ten_bai_tap'] as String?) ?? localEx.name,
              description: (row['mo_ta'] as String?) ?? localEx.description,
              icon: localEx.icon,
              instructions: listInstructions,
              isDurationBased:
                  (row['tinh_theo_thoi_gian'] as bool?) ??
                  localEx.isDurationBased,
              targetValue:
                  (row['muc_tieu_so_lan'] as num?)?.toInt() ??
                  localEx.targetValue,
              difficulty: (row['do_kho'] as String?) ?? localEx.difficulty,
              caloriesPerMin:
                  (row['calo_moi_phut'] as num?)?.toDouble() ??
                  localEx.caloriesPerMin,
              category: (row['nhom_bai_tap'] as String?) ?? localEx.category,
              focusArea:
                  (row['vung_co_tac_dong'] as String?) ?? localEx.focusArea,
              equipment: (row['dung_cu'] as String?) ?? localEx.equipment,
              isAiEnabled: (row['ho_tro_ai'] as bool?) ?? localEx.isAiEnabled,
              estimatedDurationSeconds:
                  (row['thoi_gian_uoc_tinh_giay'] as num?)?.toInt() ??
                  localEx.estimatedDurationSeconds,
              benefits: listBenefits,
            ),
          );
        }

        setState(() {
          _exercisesList = updatedList;
        });
      }
    } catch (e) {
      debugPrint('Lỗi tải bài tập động: $e');
    }
  }

  void _showPhysicalSurveyDialog({
    required String currentName,
    required double currentWeight,
    required double currentHeight,
    required int currentAge,
    required String currentGender ,
  }) {
    final formKey = GlobalKey<FormState>();
    final weightController = TextEditingController(
      text: currentWeight > 0 ? currentWeight.toString() : '',
    );
    final heightController = TextEditingController(
      text: currentHeight > 0 ? currentHeight.toString() : '',
    );
    final ageController = TextEditingController(
      text: currentAge > 0 ? currentAge.toString() : '',
    );
    
    String selectedGender = currentGender.trim().toLowerCase() == 'female'
        ? 'female'
        : 'male';
    bool isSavingLocal = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return PopScope(
          canPop: false,
          child: StatefulBuilder(
            builder: (context, setDialogState) {
              return AlertDialog(
                backgroundColor: AppTheme.cardBackground,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                title: const Column(
                  children: [
                    Icon(
                      Icons.settings_accessibility_rounded,
                      color: AppTheme.neonGreen,
                      size: 40,
                    ),
                    SizedBox(height: 12),
                    Text(
                      'Khảo Sát Thể Chất Của Bạn',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                      ),
                    ),
                  ],
                ),
                content: SingleChildScrollView(
                  child: Form(
                    key: formKey,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          'Để AI đề xuất bài tập và thực đơn ăn uống hợp lý nhất, vui lòng cung cấp chỉ số chiều cao, cân nặng và tuổi của bạn:',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: AppTheme.textSecondary,
                            fontSize: 12,
                            height: 1.4,
                          ),
                        ),
                        const SizedBox(height: 20),

                        // Chiều cao
                        TextFormField(
                          controller: heightController,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          style: const TextStyle(color: Colors.white),
                          decoration: InputDecoration(
                            labelText: 'Chiều cao (cm)',
                            labelStyle: const TextStyle(color: Colors.grey),
                            prefixIcon: const Icon(
                              Icons.height,
                              color: AppTheme.neonGreen,
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(
                                color: Colors.white24,
                              ),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(
                                color: AppTheme.neonGreen,
                              ),
                            ),
                          ),
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return 'Vui lòng nhập chiều cao';
                            }
                            final val = double.tryParse(value);
                            if (val == null || val <= 50 || val > 250) {
                              return 'Chiều cao không hợp lệ (50 - 250 cm)';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),

                        // Cân nặng
                        TextFormField(
                          controller: weightController,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          style: const TextStyle(color: Colors.white),
                          decoration: InputDecoration(
                            labelText: 'Cân nặng (kg)',
                            labelStyle: const TextStyle(color: Colors.grey),
                            prefixIcon: const Icon(
                              Icons.monitor_weight,
                              color: AppTheme.neonGreen,
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(
                                color: Colors.white24,
                              ),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(
                                color: AppTheme.neonGreen,
                              ),
                            ),
                          ),
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return 'Vui lòng nhập cân nặng';
                            }
                            final val = double.tryParse(value);
                            if (val == null || val <= 30 || val > 300) {
                              return 'Cân nặng không hợp lệ (30 - 300 kg)';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),

                        DropdownButtonFormField<String>(
                          value: selectedGender,
                          dropdownColor: AppTheme.cardBackground,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                          ),
                          decoration: InputDecoration(
                            labelText: 'Giới tính',
                            labelStyle: const TextStyle(
                              color: AppTheme.textSecondary,
                            ),
                            prefixIcon: const Icon(
                              Icons.people_outline,
                              color: AppTheme.neonGreen,
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: const BorderSide(
                                color: Colors.white12,
                              ),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: const BorderSide(
                                color: AppTheme.neonGreen,
                                width: 1.5,
                              ),
                            ),
                          ),
                          items: const [
                            DropdownMenuItem(
                              value: 'male',
                              child: Text(
                                'Nam',
                                style: TextStyle(color: Colors.white),
                              ),
                            ),
                            DropdownMenuItem(
                              value: 'female',
                              child: Text(
                                'Nữ',
                                style: TextStyle(color: Colors.white),
                              ),
                            ),
                          ],
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return 'Vui lòng chọn giới tính';
                            }
                            return null;
                          },
                          onChanged: (val) {
                            if (val != null) {
                              setDialogState(() {
                                selectedGender = val;
                              });
                            }
                          },
                        ),
                        const SizedBox(height: 16),

                        // Tuổi
                        TextFormField(
                          controller: ageController,
                          keyboardType: TextInputType.number,
                          style: const TextStyle(color: Colors.white),
                          decoration: InputDecoration(
                            labelText: 'Độ tuổi',
                            labelStyle: const TextStyle(color: Colors.grey),
                            prefixIcon: const Icon(
                              Icons.cake,
                              color: AppTheme.neonGreen,
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(
                                color: Colors.white24,
                              ),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(
                                color: AppTheme.neonGreen,
                              ),
                            ),
                          ),
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return 'Vui lòng nhập tuổi';
                            }
                            final val = int.tryParse(value);
                            if (val == null || val <= 5 || val > 120) {
                              return 'Tuổi không hợp lệ (5 - 120)';
                            }
                            return null;
                          },
                        ),
                      ],
                    ),
                  ),
                ),
                actions: [
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: isSavingLocal
                          ? null
                          : () async {
                              if (!formKey.currentState!.validate()) return;
                              setDialogState(() {
                                isSavingLocal = true;
                              });

                              try {
                                final double weight = double.parse(
                                  weightController.text,
                                );
                                final double height = double.parse(
                                  heightController.text,
                                );
                                final int age = int.parse(ageController.text);

                                await _authService.updateUserProfile(
                                  fullName: currentName.isNotEmpty
                                      ? currentName
                                      : 'Trainer',
                                  weight: weight,
                                  height: height,
                                  age: age,
                                  gender: selectedGender,
                                );

                                if (context.mounted) {
                                  Navigator.pop(context); // Đóng dialog
                                  _loadDashboardData();
                                }
                              } catch (e) {
                                debugPrint('Lỗi lưu khảo sát: $e');
                              } finally {
                                setDialogState(() {
                                  isSavingLocal = false;
                                });
                              }
                            },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.neonGreen,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: isSavingLocal
                          ? const SizedBox(
                              height: 18,
                              width: 18,
                              child: CircularProgressIndicator(
                                color: Colors.black,
                                strokeWidth: 2,
                              ),
                            )
                          : const Text(
                              'HOÀN THÀNH',
                              style: TextStyle(
                                color: Colors.black,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.8,
                              ),
                            ),
                    ),
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }

  void _handleProfileClick() {
    if (!_isSupabaseInitialized) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: AppTheme.cardBackground,
          title: const Row(
            children: [
              Icon(Icons.cloud_off, color: Colors.amber),
              SizedBox(width: 8),
              Text('Chế độ Offline'),
            ],
          ),
          content: const Text(
            'Chức năng Trang cá nhân yêu cầu cấu hình cơ sở dữ liệu Supabase.\n\nVui lòng điền thông số URL và Key ở file main.dart để trải nghiệm trực tuyến!',
            style: TextStyle(height: 1.4),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text(
                'Đồng ý',
                style: TextStyle(color: AppTheme.neonGreen),
              ),
            ),
          ],
        ),
      );
      return;
    }

    // Nếu đã có Supabase, chuyển hướng tới trang cá nhân
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ProfileScreen(cameras: widget.cameras),
      ),
    ).then((_) {
      // Reload dữ liệu khi quay lại từ trang cá nhân (đề phòng họ  cân nặng/chiều cao/họ tên)
      _loadDashboardData();
    });
  }

  Future<void> _syncPendingData() async {
    final client = Supabase.instance.client;
    final user = client.auth.currentUser;
    if (user == null || user.id == 'guest') return;

    try {
      final bool didSync = await DatabaseService().syncPendingWorkouts();
      if (didSync && mounted) {
        // Sau khi sync thành công, cập nhật lại biểu đồ và chỉ số thống kê trên Dashboard
        _loadDashboardData();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Đã tự động đồng bộ kết quả tập luyện offline thành công!'),
            backgroundColor: AppTheme.neonGreen,
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      print('[DashboardSync] Đồng bộ lịch sử tập offline thất bại: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final exercises = _exercisesList;

    return Scaffold(
      body: SafeArea(
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            // 1. THANH TIÊU ĐỀ CHÀO MỪNG (HEADER BANNER)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20.0,
                  vertical: 24.0,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Xin chào, $_userName! 👋',
                              style: const TextStyle(
                                fontSize: 14,
                                color: AppTheme.textSecondary,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 6),
                            const Text(
                              'Sẵn sàng Luyện tập',
                              style: TextStyle(
                                fontSize: 26,
                                fontWeight: FontWeight.w900,
                                color: Colors.white,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ],
                        ),

                        // Nút Avatar mở Trang cá nhân
                        GestureDetector(
                          onTap: _handleProfileClick,
                          child: Container(
                            padding: const EdgeInsets.all(2),
                            decoration: const BoxDecoration(
                              color: AppTheme.neonGreen,
                              shape: BoxShape.circle,
                            ),
                            child: const CircleAvatar(
                              radius: 22,
                              backgroundColor: AppTheme.cardBackground,
                              child: Icon(Icons.person, color: Colors.white),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // BẢNG ĐIỀU KHIỂN HÀNG NGÀY TRỰC QUAN (DAILY PROGRESS PANEL)
                    Container(
                      padding: const EdgeInsets.all(18),
                      decoration:
                          AppTheme.glassDecoration(
                            color: AppTheme.cardBackground.withValues(
                              alpha: 0.4,
                            ),
                            borderRadius: 24,
                          ).copyWith(
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.05),
                              width: 1,
                            ),
                          ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Row(
                                children: [
                                  Icon(
                                    Icons.today,
                                    color: AppTheme.neonGreen,
                                    size: 20,
                                  ),
                                  SizedBox(width: 8),
                                  Text(
                                    'Điểm Danh & Chuỗi Tập',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14.5,
                                    ),
                                  ),
                                ],
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: AppTheme.neonGreen.withValues(
                                    alpha: 0.12,
                                  ),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  'Chuỗi: $_checkInStreak',
                                  style: const TextStyle(
                                    color: AppTheme.neonGreen,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 11.5,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const Divider(color: Colors.white10, height: 24),

                          // Bảng 7 ngày tuần hiện tại
                          _isLoadingCheckIn
                              ? const Center(
                                  child: SizedBox(
                                    height: 20,
                                    width: 20,
                                    child: CircularProgressIndicator(
                                      color: AppTheme.neonGreen,
                                      strokeWidth: 1.5,
                                    ),
                                  ),
                                )
                              : Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: _weekCheckInStatus.map((day) {
                                    final bool isToday = day['isToday'] as bool;
                                    final bool hasChecked =
                                        day['hasChecked'] as bool;
                                    final bool isFuture =
                                        day['isFuture'] as bool;

                                    Color indicatorColor = Colors.white10;
                                    Widget indicatorWidget = const SizedBox(
                                      width: 10,
                                      height: 10,
                                    );

                                    if (hasChecked) {
                                      indicatorColor = AppTheme.neonGreen
                                          .withValues(alpha: 0.2);
                                      indicatorWidget = const Icon(
                                        Icons.check,
                                        color: AppTheme.neonGreen,
                                        size: 12,
                                      );
                                    } else if (isToday) {
                                      indicatorColor = Colors.orange.withValues(
                                        alpha: 0.2,
                                      );
                                      indicatorWidget = Container(
                                        width: 6,
                                        height: 6,
                                        decoration: const BoxDecoration(
                                          color: Colors.orange,
                                          shape: BoxShape.circle,
                                        ),
                                      );
                                    } else if (isFuture) {
                                      indicatorColor = Colors.transparent;
                                      indicatorWidget = Container(
                                        width: 10,
                                        height: 10,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          border: Border.all(
                                            color: Colors.white24,
                                            width: 0.8,
                                          ),
                                        ),
                                      );
                                    } else {
                                      indicatorColor = Colors.white10;
                                      indicatorWidget = const Icon(
                                        Icons.close,
                                        color: Colors.white24,
                                        size: 10,
                                      );
                                    }

                                    return Column(
                                      children: [
                                        Text(
                                          day['name'] as String,
                                          style: TextStyle(
                                            color: isToday
                                                ? AppTheme.neonGreen
                                                : Colors.grey,
                                            fontWeight: isToday
                                                ? FontWeight.bold
                                                : FontWeight.normal,
                                            fontSize: 10.5,
                                          ),
                                        ),
                                        const SizedBox(height: 6),
                                        Container(
                                          width: 24,
                                          height: 24,
                                          decoration: BoxDecoration(
                                            color: indicatorColor,
                                            shape: BoxShape.circle,
                                            border: Border.all(
                                              color: hasChecked
                                                  ? AppTheme.neonGreen
                                                        .withValues(alpha: 0.4)
                                                  : isToday
                                                  ? Colors.orange
                                                  : Colors.white12,
                                              width: 0.8,
                                            ),
                                          ),
                                          child: Center(child: indicatorWidget),
                                        ),
                                      ],
                                    );
                                  }).toList(),
                                ),

                          if (!_hasCheckedInToday) ...[
                            const SizedBox(height: 16),
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton.icon(
                                onPressed: _handleCheckIn,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppTheme.neonGreen,
                                  foregroundColor: Colors.black,
                                  elevation: 0,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 10,
                                  ),
                                ),
                                icon: const Icon(Icons.edit_calendar, size: 18),
                                label: const Text(
                                  'ĐIỂM DANH HÔM NAY (+10 XP)',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                            ),
                          ],

                          const Divider(color: Colors.white10, height: 28),

                          // Bảng số liệu tập luyện hôm nay
                          _isLoadingStats
                              ? const Center(
                                  child: SizedBox(
                                    height: 20,
                                    width: 20,
                                    child: CircularProgressIndicator(
                                      color: AppTheme.neonGreen,
                                      strokeWidth: 1.5,
                                    ),
                                  ),
                                )
                              : Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceAround,
                                  children: [
                                    _buildQuickStatItem(
                                      Icons.local_fire_department,
                                      'Kcal tiêu hao',
                                      '${_totalCalories.toStringAsFixed(0)} kcal',
                                      Colors.orange,
                                    ),
                                    Container(
                                      height: 32,
                                      width: 1,
                                      color: Colors.white12,
                                    ),
                                    _buildQuickStatItem(
                                      Icons.timer,
                                      'Thời gian tập',
                                      '$_totalMinutes phút',
                                      AppTheme.neonBlue,
                                    ),
                                    Container(
                                      height: 32,
                                      width: 1,
                                      color: Colors.white12,
                                    ),
                                    _buildQuickStatItem(
                                      Icons.emoji_events,
                                      'Bài tập',
                                      '${exercises.length} bài AI',
                                      AppTheme.neonGreen,
                                    ),
                                  ],
                                ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // ĐỀ XUẤT AI HLV CÁ NHÂN (AI PERSONAL COACH CARD)
                    GestureDetector(
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) =>
                                RecommendationScreen(cameras: widget.cameras),
                          ),
                        ).then((_) {
                          _loadDashboardData();
                        });
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 14,
                        ),
                        decoration:
                            AppTheme.glassDecoration(
                              color: AppTheme.neonGreen.withValues(alpha: 0.1),
                              borderRadius: 20,
                            ).copyWith(
                              border: Border.all(
                                color: AppTheme.neonGreen.withValues(
                                  alpha: 0.2,
                                ),
                                width: 1,
                              ),
                            ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: AppTheme.neonGreen.withValues(
                                  alpha: 0.15,
                                ),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.psychology,
                                color: AppTheme.neonGreen,
                                size: 24,
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'AI HLV - Đề Xuất Bài Tập',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'Đề xuất số rep/calo dựa theo chỉ số BMI cơ thể.',
                                    style: TextStyle(
                                      color: Colors.white.withValues(
                                        alpha: 0.6,
                                      ),
                                      fontSize: 10.5,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const Icon(
                              Icons.arrow_forward_ios,
                              color: AppTheme.neonGreen,
                              size: 12,
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 12),

                    // Dedicated Lịch sử tập luyện card
                    GestureDetector(
                      onTap: _showWorkoutHistory,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 14,
                        ),
                        decoration:
                            AppTheme.glassDecoration(
                              color: AppTheme.neonBlue.withValues(alpha: 0.1),
                              borderRadius: 20,
                            ).copyWith(
                              border: Border.all(
                                color: AppTheme.neonBlue.withValues(alpha: 0.2),
                                width: 1,
                              ),
                            ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: AppTheme.neonBlue.withValues(
                                  alpha: 0.15,
                                ),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.history,
                                color: AppTheme.neonBlue,
                                size: 24,
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Nhật Ký Lịch Sử & Điểm Danh',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'Xem tiến trình bài tập hoàn chỉnh, tập lỗi và chuỗi điểm danh.',
                                    style: TextStyle(
                                      color: Colors.white.withValues(
                                        alpha: 0.6,
                                      ),
                                      fontSize: 10.5,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const Icon(
                              Icons.arrow_forward_ios,
                              color: AppTheme.neonBlue,
                              size: 12,
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 24),

                    if (_todayDraftWorkout != null) ...[
                      Container(
                        padding: const EdgeInsets.all(14),
                        margin: const EdgeInsets.only(bottom: 16),
                        decoration: BoxDecoration(
                          color: Colors.orange.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: Colors.orange.withValues(alpha: 0.25),
                          ),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.play_circle_fill,
                              color: Colors.orange,
                              size: 26,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Bài đang lưu tạm: ${_todayDraftWorkout!['exerciseName'] ?? _todayDraftWorkout!['exerciseType']}',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Mục tiêu: ${_todayDraftWorkout!['targetCount']} ${(_todayDraftWorkout!['exerciseType'] as String?) == 'plank' ? 'giây' : 'lần'}',
                                    style: TextStyle(
                                      color: Colors.white.withValues(
                                        alpha: 0.72,
                                      ),
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            // NÚT XÓA MỚI ĐƯỢC THÊM VÀO ĐÂY
                            TextButton(
                              onPressed: () async {
                                // Hiển thị hộp thoại xác nhận trước khi xóa (Tùy chọn, giúp tránh bấm nhầm)
                                final confirm = await showDialog<bool>(
                                  context: context,
                                  builder: (context) => AlertDialog(
                                    title: const Text('Xóa bài tập tạm?'),
                                    content: const Text(
                                      'Bạn có chắc chắn muốn xóa bài tập nháp này không?',
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.pop(context, false),
                                        child: const Text('Hủy'),
                                      ),
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.pop(context, true),
                                        child: const Text(
                                          'Xóa',
                                          style: TextStyle(color: Colors.red),
                                        ),
                                      ),
                                    ],
                                  ),
                                );

                                if (confirm == true) {
                                  await _clearTodayDraftWorkout();
                                }
                              },
                              child: const Text(
                                'Xóa',
                                style: TextStyle(
                                  color: Colors
                                      .redAccent, // Màu đỏ để phân biệt với nút Tiếp tục
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            TextButton(
                              onPressed: () async {
                                final draft = _todayDraftWorkout;
                                if (draft == null) return;
                                final exerciseTypeName =
                                    draft['exerciseType'] as String?;
                                final exercise = _exercisesList.firstWhere(
                                  (item) => item.type.name == exerciseTypeName,
                                  orElse: () => _exercisesList.first,
                                );
                                await Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => WorkoutScreen(
                                      exercise: exercise,
                                      cameras: widget.cameras,
                                      targetCount: (draft['targetCount'] as num)
                                          .toInt(),
                                      noSplit:
                                          draft['noSplit'] as bool? ?? false,
                                      sourceTag: draft['sourceTag'] as String?,
                                      initialCompletedCount:
                                          (draft['completedCount'] as num?)
                                              ?.toInt() ??
                                          0,
                                    ),
                                  ),
                                );

                                await _refreshTodayDraftWorkout();
                              },
                              child: const Text(
                                'Tiếp tục',
                                style: TextStyle(
                                  color: AppTheme.neonGreen,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],

                    const Text(
                      'BÀI TẬP VỚI AI ĐỒNG HÀNH',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.neonGreen,
                        letterSpacing: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // 3. DANH SÁCH CÁC THẺ BÀI TẬP DẠNG LƯỚI KHOA HỌC (SCIENTIFIC GRID)
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 20.0),
              sliver: SliverGrid(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  mainAxisSpacing: 14,
                  crossAxisSpacing: 14,
                  childAspectRatio: 0.95,
                ),
                delegate: SliverChildBuilderDelegate((context, index) {
                  final exercise = exercises[index];
                  return _buildExerciseGridTile(context, exercise);
                }, childCount: exercises.length),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickStatItem(
    IconData icon,
    String label,
    String value,
    Color color, {
    VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _buildExerciseGridTile(BuildContext context, ExerciseDetail exercise) {
    final currentTarget =
        _selectedTargets[exercise.type] ?? exercise.targetValue;

    return GestureDetector(
      onTap: () => _showExerciseDetailsBottomSheet(context, exercise),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration:
            AppTheme.glassDecoration(
              color: AppTheme.cardBackground.withValues(alpha: 0.35),
              borderRadius: 20,
            ).copyWith(
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.08),
                width: 1,
              ),
            ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppTheme.neonGreen.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    exercise.icon,
                    color: AppTheme.neonGreen,
                    size: 20,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.purple.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    exercise.difficulty,
                    style: const TextStyle(
                      color: Colors.purpleAccent,
                      fontWeight: FontWeight.bold,
                      fontSize: 9,
                    ),
                  ),
                ),
              ],
            ),

            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  exercise.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '~${exercise.caloriesPerMin} kcal/phút',
                  style: const TextStyle(
                    color: Colors.orangeAccent,
                    fontSize: 10.5,
                  ),
                ),
              ],
            ),

            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '$currentTarget ${exercise.isDurationBased ? "giây" : "reps"}',
                  style: const TextStyle(
                    color: Colors.grey,
                    fontWeight: FontWeight.bold,
                    fontSize: 11.5,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: const BoxDecoration(
                    color: AppTheme.neonGreen,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.play_arrow,
                    color: Colors.black,
                    size: 14,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showExerciseDetailsBottomSheet(
    BuildContext context,
    ExerciseDetail exercise,
  ) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.cardBackground,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final isDraftForThisExercise =
                _todayDraftWorkout != null &&
                _todayDraftWorkout!['exerciseType'] == exercise.type.name;

            final currentTarget = isDraftForThisExercise
                ? (_todayDraftWorkout!['targetCount'] as num).toInt()
                : (_selectedTargets[exercise.type] ?? exercise.targetValue);
            final isNoSplit = isDraftForThisExercise
                ? (_todayDraftWorkout!['noSplit'] as bool? ?? false)
                : (_noSplitTargets[exercise.type] ?? false);

            return Padding(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 10,
                bottom: MediaQuery.of(context).viewInsets.bottom + 24,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        margin: const EdgeInsets.only(bottom: 20),
                        decoration: BoxDecoration(
                          color: Colors.white24,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),

                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AppTheme.neonGreen.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Icon(
                            exercise.icon,
                            color: AppTheme.neonGreen,
                            size: 28,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                exercise.name,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 18,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.purple.withValues(
                                        alpha: 0.15,
                                      ),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      'Độ khó: ${exercise.difficulty}',
                                      style: const TextStyle(
                                        color: Colors.purpleAccent,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 10,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.orange.withValues(
                                        alpha: 0.15,
                                      ),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      '~${exercise.caloriesPerMin} kcal/phút',
                                      style: const TextStyle(
                                        color: Colors.orangeAccent,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 10,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),

                    Text(
                      exercise.description,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.7),
                        fontSize: 13,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 20),

                    const Text(
                      'AI HƯỚNG DẪN ĐỘNG TÁC:',
                      style: TextStyle(
                        color: AppTheme.neonGreen,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                        letterSpacing: 1.0,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ...exercise.instructions.map(
                      (step) => Padding(
                        padding: const EdgeInsets.only(bottom: 8.0),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              '• ',
                              style: TextStyle(
                                color: AppTheme.neonGreen,
                                fontSize: 16,
                              ),
                            ),
                            Expanded(
                              child: Text(
                                step,
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.8),
                                  fontSize: 12.5,
                                  height: 1.4,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),

                    if (!isDraftForThisExercise) ...[
                      if (!exercise.isDurationBased) ...[
                        const Text(
                          'CHỌN SỐ LẦN TẬP (REPS):',
                          style: TextStyle(
                            color: AppTheme.neonGreen,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                            letterSpacing: 1.0,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: ExerciseDetail.targetOptions.map((option) {
                            final isSelected = currentTarget == option;
                            return ChoiceChip(
                              label: Text('$option lần'),
                              selected: isSelected,
                              selectedColor: AppTheme.neonGreen,
                              backgroundColor: Colors.white.withValues(
                                alpha: 0.05,
                              ),
                              labelStyle: TextStyle(
                                color: isSelected
                                    ? Colors.black
                                    : Colors.white70,
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                              onSelected: (_) {
                                setModalState(() {
                                  _selectedTargets[exercise.type] = option;
                                });
                                setState(() {});
                              },
                            );
                          }).toList(),
                        ),
                      ] else ...[
                        const Text(
                          'CHỌN SỐ GIÂY GIỮ PLANK:',
                          style: TextStyle(
                            color: AppTheme.neonGreen,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                            letterSpacing: 1.0,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [20, 30, 45, 60, 90, 120].map((option) {
                            final isSelected = currentTarget == option;
                            return ChoiceChip(
                              label: Text('$option giây'),
                              selected: isSelected,
                              selectedColor: AppTheme.neonGreen,
                              backgroundColor: Colors.white.withValues(
                                alpha: 0.05,
                              ),
                              labelStyle: TextStyle(
                                color: isSelected
                                    ? Colors.black
                                    : Colors.white70,
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                              onSelected: (_) {
                                setModalState(() {
                                  _selectedTargets[exercise.type] = option;
                                });
                                setState(() {});
                              },
                            );
                          }).toList(),
                        ),
                      ],
                      const SizedBox(height: 16),

                      SwitchListTile(
                        title: const Text(
                          'Tập liên tục (không chia hiệp)',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        subtitle: const Text(
                          'Bỏ qua đếm ngược và chia chặng nghỉ giữa giờ.',
                          style: TextStyle(color: Colors.grey, fontSize: 11),
                        ),
                        value: isNoSplit,
                        activeThumbColor: AppTheme.neonGreen,
                        contentPadding: EdgeInsets.zero,
                        onChanged: (val) {
                          setModalState(() {
                            _noSplitTargets[exercise.type] = val;
                          });
                          setState(() {});
                        },
                      ),
                    ] else ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppTheme.neonGreen.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: AppTheme.neonGreen.withValues(alpha: 0.3),
                          ),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.info_outline,
                              color: AppTheme.neonGreen,
                              size: 20,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'Bạn có bài tập lưu tạm hôm nay: đã hoàn thành ${_todayDraftWorkout!['completedCount'] ?? 0}/${_todayDraftWorkout!['targetCount']} ${exercise.isDurationBased ? 'giây' : 'lần'}. Bấm "Tập tiếp" để tiếp tục.',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 24),

                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () async {
                          final navigatorContext = context;
                          if (navigatorContext.mounted) {
                            Navigator.pop(navigatorContext);
                          }
                          if (navigatorContext.mounted) {
                            await Navigator.push(
                              navigatorContext,
                              MaterialPageRoute(
                                builder: (context) => WorkoutScreen(
                                  exercise: exercise,
                                  cameras: widget.cameras,
                                  targetCount: currentTarget,
                                  noSplit: isNoSplit,
                                  sourceTag: 'exercise_list',
                                  initialCompletedCount: isDraftForThisExercise
                                      ? (_todayDraftWorkout!['completedCount']
                                                    as num?)
                                                ?.toInt() ??
                                            0
                                      : 0,
                                ),
                              ),
                            );

                            await _refreshTodayDraftWorkout();
                            _loadDashboardData();
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.neonGreen,
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        icon: const Icon(Icons.play_arrow, size: 20),
                        label: Text(
                          isDraftForThisExercise
                              ? 'TẬP TIẾP'
                              : 'BẮT ĐẦU LUYỆN TẬP NGAY',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}
