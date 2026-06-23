import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/theme/app_theme.dart';
import '../models/exercise.dart';
import '../services/auth_service.dart';
import '../services/database_service.dart';
import 'profile_screen.dart';
import 'workout/workout_screen.dart';

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

  @override
  void initState() {
    super.initState();
    _loadDashboardData();
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

    setState(() {
      _isLoadingStats = true;
    });

    try {
      // 1. Tải thông tin người dùng
      final profile = await _authService.getCurrentUserProfile();
      if (profile != null && mounted) {
        setState(() {
          _userName = profile['full_name'] ?? 'Trainer';
        });
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
      // Reload dữ liệu khi quay lại từ trang cá nhân (đề phòng họ sửa cân nặng/chiều cao/họ tên)
      _loadDashboardData();
    });
  }

  @override
  Widget build(BuildContext context) {
    final exercises = ExerciseDetail.defaultExercises;

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
                    const SizedBox(height: 24),

                    // 2. KHU VỰC THỐNG KÊ NHANH (QUICK STATS PANEL)
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: AppTheme.glassDecoration(
                        color: AppTheme.cardBackground.withValues(alpha: 0.5),
                        borderRadius: 20,
                      ),
                      child: _isLoadingStats
                          ? const Center(
                              child: SizedBox(
                                height: 24,
                                width: 24,
                                child: CircularProgressIndicator(
                                  color: AppTheme.neonGreen,
                                  strokeWidth: 2,
                                ),
                              ),
                            )
                          : Row(
                              mainAxisAlignment: MainAxisAlignment.spaceAround,
                              children: [
                                _buildQuickStatItem(
                                  Icons.local_fire_department,
                                  'Kcal',
                                  '${_totalCalories.toStringAsFixed(0)} kcal',
                                  Colors.orange,
                                ),
                                Container(
                                  height: 36,
                                  width: 1,
                                  color: Colors.white12,
                                ),
                                _buildQuickStatItem(
                                  Icons.timer,
                                  'Thời gian',
                                  '$_totalMinutes phút',
                                  AppTheme.neonBlue,
                                ),
                                Container(
                                  height: 36,
                                  width: 1,
                                  color: Colors.white12,
                                ),
                                _buildQuickStatItem(
                                  Icons.emoji_events,
                                  'Bài tập',
                                  '4 bài AI',
                                  AppTheme.neonGreen,
                                ),
                              ],
                            ),
                    ),
                    const SizedBox(height: 28),

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

            // 3. DANH SÁCH CÁC THẺ BÀI TẬP (EXERCISE CARDS GRID/LIST)
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 20.0),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate((context, index) {
                  final exercise = exercises[index];
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 16.0),
                    child: _buildExerciseCard(context, exercise),
                  );
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
    Color color,
  ) {
    return Column(
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
    );
  }

  Widget _buildExerciseCard(BuildContext context, ExerciseDetail exercise) {
    return Container(
      decoration: AppTheme.glassDecoration(
        color: AppTheme.cardBackground,
        borderRadius: 20,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Theme(
          data: ThemeData.dark().copyWith(
            dividerColor: Colors.transparent,
            colorScheme: const ColorScheme.dark(primary: AppTheme.neonGreen),
          ),
          child: ExpansionTile(
            leading: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppTheme.neonGreen.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(exercise.icon, color: AppTheme.neonGreen, size: 24),
            ),
            title: Text(
              exercise.name,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            subtitle: Text(
              exercise.description,
              style: const TextStyle(
                fontSize: 12,
                color: AppTheme.textSecondary,
              ),
            ),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Divider(color: Colors.white12),
                    const SizedBox(height: 8),
                    // Thông tin phụ: Độ khó, calo tiêu hao
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _buildBadge(
                          Icons.speed,
                          'Độ khó: ${exercise.difficulty}',
                          Colors.purpleAccent,
                        ),
                        _buildBadge(
                          Icons.local_fire_department,
                          '~${exercise.caloriesPerMin} kcal/phút',
                          Colors.orangeAccent,
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'HƯỚNG DẪN CỦA AI TRONG KHI TẬP:',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.neonGreen,
                        letterSpacing: 1.0,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ...exercise.instructions.map(
                      (step) => Padding(
                        padding: const EdgeInsets.only(bottom: 6.0),
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
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: AppTheme.textSecondary,
                                  height: 1.4,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (!exercise.isDurationBased) ...[
                      const Text(
                        'Chọn số lượng:',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.neonGreen,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: ExerciseDetail.targetOptions.map((option) {
                          final isSelected =
                              (_selectedTargets[exercise.type] ??
                                  exercise.targetValue) ==
                              option;
                          return ChoiceChip(
                            label: Text('$option'),
                            selected: isSelected,
                            selectedColor: AppTheme.neonGreen,
                            backgroundColor: AppTheme.cardBackground,
                            labelStyle: TextStyle(
                              color: isSelected ? Colors.black : Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                            onSelected: (_) {
                              setState(() {
                                _selectedTargets[exercise.type] = option;
                              });
                            },
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 12),
                      Builder(
                        builder: (context) {
                          final selectedTarget =
                              _selectedTargets[exercise.type] ??
                              exercise.targetValue;
                          final noSplit =
                              _noSplitTargets[exercise.type] ?? false;
                          final plan = noSplit
                              ? [selectedTarget]
                              : ExerciseDetail.computeSetPlan(selectedTarget);
                          final planText = noSplit
                              ? 'Không chia rep — 1 set ($selectedTarget)'
                              : plan.isNotEmpty
                              ? '${plan.length} set (${plan.map((value) => '$value').join(' + ')})'
                              : '';
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Tổng mục tiêu: $selectedTarget lần',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      'Kế hoạch set: $planText',
                                      style: const TextStyle(
                                        color: AppTheme.textSecondary,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              if (!exercise.isDurationBased) ...[
                                const SizedBox(height: 12),
                                Row(
                                  children: [
                                    Switch(
                                      value: noSplit,
                                      activeThumbColor: AppTheme.neonGreen,
                                      onChanged: (value) {
                                        setState(() {
                                          _noSplitTargets[exercise.type] =
                                              value;
                                        });
                                      },
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        'Không chia rep trước khi bắt đầu',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ],
                          );
                        },
                      ),
                      const SizedBox(height: 16),
                    ],

                    // Nút Bắt đầu
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () {
                          final selectedTarget =
                              _selectedTargets[exercise.type] ??
                              exercise.targetValue;
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => WorkoutScreen(
                                exercise: exercise,
                                targetCount: selectedTarget,
                                noSplit:
                                    _noSplitTargets[exercise.type] ?? false,
                                cameras: widget.cameras,
                              ),
                            ),
                          ).then((_) {
                            // Tải lại chỉ số thống kê khi tập xong quay lại Dashboard
                            _loadDashboardData();
                          });
                        },
                        icon: const Icon(
                          Icons.play_arrow_rounded,
                          color: Colors.black,
                          size: 24,
                        ),
                        label: const Text(
                          'BẮT ĐẦU LUYỆN TẬP',
                          style: TextStyle(
                            color: Colors.black,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.8,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.neonGreen,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBadge(IconData icon, String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 6),
          Text(
            text,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
