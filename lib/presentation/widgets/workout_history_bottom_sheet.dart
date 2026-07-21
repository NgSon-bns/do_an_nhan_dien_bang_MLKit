import 'package:flutter/material.dart';
import 'package:demo/core/theme/app_theme.dart';
import 'package:demo/data/services/database_service.dart';
import 'package:demo/data/services/check_in_service.dart';

class WorkoutHistoryBottomSheet extends StatefulWidget {
  final DatabaseService databaseService;

  const WorkoutHistoryBottomSheet({
    super.key,
    required this.databaseService,
  });

  @override
  State<WorkoutHistoryBottomSheet> createState() => _WorkoutHistoryBottomSheetState();
}

class _WorkoutHistoryBottomSheetState extends State<WorkoutHistoryBottomSheet> {
  // Mặc định là null để hiển thị toàn bộ lịch sử tập luyện ban đầu
  DateTime? _selectedDate;

  // Hàm chuyển đổi tên kỹ thuật dạng "pushUp::40::custom" thành tên tiếng Việt thân thiện
  String _getFriendlyExerciseName(String rawName) {
    final parts = rawName.split('::');
    final mainName = parts.isNotEmpty ? parts[0] : rawName;

    switch (mainName) {
      case 'pushUp':
      case 'push_up':
        return 'Hít đất (Push Up)';
      case 'squat':
        return 'Gánh đùi (Squat)';
      case 'plank':
        return 'Tấm ván (Plank)';
      case 'jumpingJack':
      case 'jumping_jack':
        return 'Nhảy dang tay (Jumping Jack)';
      case 'burpee':
        return 'Hít đất bật nhảy (Burpee)';
      case 'walkingLunge':
      case 'walking_lunge':
        return 'Bước chùng chân (Walking Lunge)';
      default:
        if (mainName.isEmpty) return 'Bài tập';
        return mainName[0].toUpperCase() + mainName.substring(1);
    }
  }

  // Hàm mở bộ chọn ngày của hệ thống Flutter
  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.dark(
              primary: AppTheme.neonGreen, // Màu chủ đạo của lịch chọn
              onPrimary: Colors.black,
              surface: Colors.black87,
              onSurface: Colors.white,
            ),
            textButtonTheme: TextButtonThemeData(
              style: TextButton.styleFrom(
                foregroundColor: AppTheme.neonGreen,
              ),
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null && picked != _selectedDate) {
      setState(() {
        _selectedDate = picked;
      });
    }
  }

  // So sánh xem 2 mốc thời gian DateTime có cùng ngày/tháng/năm không
  bool _isSameDay(DateTime date1, DateTime date2) {
    return date1.year == date2.year &&
        date1.month == date2.month &&
        date1.day == date2.day;
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return DefaultTabController(
          length: 3,
          child: FutureBuilder<List<Map<String, dynamic>>>(
            future: widget.databaseService.getRecentWorkouts(limit: 100),
            builder: (context, snapshot) {
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  children: [
                    // Thanh kéo chỉ thị đầu Bottom Sheet
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        margin: const EdgeInsets.symmetric(vertical: 16),
                        decoration: BoxDecoration(
                          color: Colors.white24,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),

                    // Header: Tiêu đề và Nút chọn ngày
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.history, color: AppTheme.neonGreen),
                            SizedBox(width: 10),
                            Text(
                              'Nhật Ký & Hoạt Động',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        // Nút chọn lịch
                        IconButton(
                          onPressed: () => _selectDate(context),
                          icon: const Icon(
                            Icons.calendar_month_outlined,
                            color: AppTheme.neonGreen,
                            size: 26,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),

                    // Khu vực hiển thị ngày đang chọn và nút bỏ chọn
                    Container(
                      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
                      decoration: BoxDecoration(
                        color: _selectedDate == null 
                            ? Colors.white.withValues(alpha: 0.04) 
                            : AppTheme.neonGreen.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: _selectedDate == null 
                              ? Colors.white.withValues(alpha: 0.05) 
                              : AppTheme.neonGreen.withValues(alpha: 0.2),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            _selectedDate == null
                                ? 'Tất cả hoạt động'
                                : 'Ngày: ${_selectedDate!.day}/${_selectedDate!.month}/${_selectedDate!.year}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                              fontSize: 15,
                            ),
                          ),
                          if (_selectedDate != null)
                            GestureDetector(
                              onTap: () {
                                setState(() {
                                  _selectedDate = null;
                                });
                              },
                              child: const Row(
                                children: [
                                  Text(
                                    'Hiện tất cả',
                                    style: TextStyle(
                                      color: AppTheme.neonGreen,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                    ),
                                  ),
                                  SizedBox(width: 4),
                                  Icon(
                                    Icons.close,
                                    color: AppTheme.neonGreen,
                                    size: 16,
                                  )
                                ],
                              ),
                            )
                          else
                            GestureDetector(
                              onTap: () {
                                setState(() {
                                  _selectedDate = DateTime.now();
                                });
                              },
                              child: const Text(
                                'Hôm nay',
                                style: TextStyle(
                                  color: AppTheme.textSecondary,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Thẻ TabBar phân chia loại lịch trình
                    const TabBar(
                      indicatorColor: AppTheme.neonGreen,
                      labelColor: AppTheme.neonGreen,
                      unselectedLabelColor: Colors.white60,
                      labelStyle: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                      tabs: [
                        Tab(text: 'Tập hoàn chỉnh'),
                        Tab(text: 'Tập lỗi/Quá sức'),
                        Tab(text: 'Điểm danh'),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Nội dung phân lớp
                    Expanded(
                      child: TabBarView(
                        children: [
                          _buildHistoryTabContent(snapshot, scrollController, isCorrectOnly: true),
                          _buildHistoryTabContent(snapshot, scrollController, isCorrectOnly: false),
                          _buildCheckInTabContent(scrollController),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildHistoryTabContent(
    AsyncSnapshot<List<Map<String, dynamic>>> snapshot,
    ScrollController scrollController, {
    required bool isCorrectOnly,
  }) {
    if (snapshot.connectionState == ConnectionState.waiting) {
      return const Center(
        child: CircularProgressIndicator(color: AppTheme.neonGreen),
      );
    }

    if (snapshot.hasError || !snapshot.hasData || snapshot.data!.isEmpty) {
      return _buildEmptyState();
    }

    final rawHistoryList = snapshot.data!;

    // Bộ lọc theo tập hoàn chỉnh vs tập lỗi và theo ngày
    final historyList = rawHistoryList.where((workout) {
      // 1. Lọc bỏ Check_in
      final String rawExerciseId = (workout['exercise_id'] ?? workout['exercise_type'] ?? '').toString();
      final lowercaseId = rawExerciseId.toLowerCase();
      if (lowercaseId.contains('check_in') || lowercaseId.contains('checkin') || lowercaseId.contains('check-in')) {
        return false;
      }

      // 2. Phân loại Hoàn chỉnh (< 5 lỗi) vs Tập lỗi (>= 5 lỗi)
      final int incorrectPostures = (workout['incorrect_postures'] ?? 0) as int;
      if (isCorrectOnly && incorrectPostures >= 5) return false;
      if (!isCorrectOnly && incorrectPostures < 5) return false;

      // 3. Lọc theo ngày
      if (_selectedDate != null) {
        if (workout['created_at'] == null) return false;
        try {
          final date = DateTime.parse(workout['created_at'].toString()).toLocal();
          return _isSameDay(date, _selectedDate!);
        } catch (_) {
          return false;
        }
      }
      return true;
    }).toList();

    if (historyList.isEmpty) {
      return _buildEmptyState();
    }

    double totalCalories = 0;
    for (var workout in historyList) {
      totalCalories += ((workout['calories_burned'] ?? 0) as num).toDouble();
    }
    final double targetCalo = 300.0;
    final double progress = (totalCalories / targetCalo).clamp(0.0, 1.0);

    return Column(
      children: [
        Row(
          children: [
            Text(
              'Số bài: ${historyList.length}',
              style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13),
            ),
            const Spacer(),
            Text(
              'Tiêu hao: ${totalCalories.toStringAsFixed(1)} kcal',
              style: const TextStyle(
                color: Colors.orangeAccent,
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
          ],
        ),
        if (isCorrectOnly) ...[
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress,
              backgroundColor: Colors.white12,
              valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.neonGreen),
              minHeight: 6,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Tiến trình ngày: ${(progress * 100).toStringAsFixed(0)}%',
                style: const TextStyle(color: Colors.white54, fontSize: 10),
              ),
              const Text(
                'Mục tiêu: 300 kcal',
                style: TextStyle(color: Colors.white54, fontSize: 10),
              ),
            ],
          ),
        ],
        const SizedBox(height: 12),
        Expanded(
          child: ListView.builder(
            controller: scrollController,
            physics: const BouncingScrollPhysics(),
            itemCount: historyList.length,
            itemBuilder: (context, index) {
              final workout = historyList[index];
              final String rawExerciseName = workout['exercise_id'] ?? workout['exercise_type'] ?? 'Bài tập';
              final String exerciseName = _getFriendlyExerciseName(rawExerciseName);
              final int duration = (workout['duration_seconds'] ?? 0) as int;
              final int reps = (workout['reps_count'] ?? 0) as int;
              final double calories = ((workout['calories_burned'] ?? 0) as num).toDouble();
              final int incorrectPostures = (workout['incorrect_postures'] ?? 0) as int;

              String formattedDate = '';
              if (workout['created_at'] != null) {
                try {
                  final date = DateTime.parse(workout['created_at'].toString()).toLocal();
                  formattedDate = _selectedDate == null
                      ? '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')} - ${date.day}/${date.month}/${date.year}'
                      : 'Bắt đầu: ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
                } catch (_) {
                  formattedDate = workout['created_at'].toString();
                }
              }

              return Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.04),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.05),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: isCorrectOnly
                            ? AppTheme.neonGreen.withValues(alpha: 0.1)
                            : AppTheme.errorRed.withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        isCorrectOnly ? Icons.check : Icons.warning_amber_rounded,
                        color: isCorrectOnly ? AppTheme.neonGreen : AppTheme.errorRed,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            exerciseName,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 14.5,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            formattedDate,
                            style: const TextStyle(
                              color: AppTheme.textSecondary,
                              fontSize: 11,
                            ),
                          ),
                          if (!isCorrectOnly) ...[
                            const SizedBox(height: 4),
                            Text(
                              'Số lỗi sai tư thế: $incorrectPostures lần',
                              style: const TextStyle(
                                color: AppTheme.errorRed,
                                fontSize: 11.5,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          '+${calories.toStringAsFixed(1)} kcal',
                          style: const TextStyle(
                            color: Colors.orangeAccent,
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          rawExerciseName.toLowerCase().contains('plank')
                              ? '$duration giây'
                              : (reps > 0 ? '$reps lần' : '$duration giây'),
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.6),
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildCheckInTabContent(ScrollController scrollController) {
    return FutureBuilder<Map<String, dynamic>>(
      future: () async {
        final checkInService = CheckInService();
        await checkInService.syncCheckInHistoryFromSupabase();
        final dates = await checkInService.getCheckInDates();
        final streak = await checkInService.getStreak();
        return {'dates': dates, 'streak': streak};
      }(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(color: AppTheme.neonGreen),
          );
        }

        if (snapshot.hasError || !snapshot.hasData) {
          return _buildEmptyState();
        }

        final data = snapshot.data!;
        final rawCheckInDates = (data['dates'] as List<dynamic>).map((e) => e.toString()).toList();
        final int streak = data['streak'] as int;

        // Lọc theo ngày
        final filteredDates = rawCheckInDates.where((dateStr) {
          if (_selectedDate == null) return true;
          try {
            final date = DateTime.parse(dateStr);
            return _isSameDay(date, _selectedDate!);
          } catch (_) {
            return false;
          }
        }).toList();

        if (filteredDates.isEmpty && streak == 0) {
          return _buildEmptyState();
        }

        // Sắp xếp ngày điểm danh mới nhất lên đầu
        filteredDates.sort((a, b) => b.compareTo(a));

        return Column(
          children: [
            // Glowing Fire Streak Card
            if (_selectedDate == null) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: streak > 0 
                        ? [const Color(0xFFFF5722), const Color(0xFFFF9800)] 
                        : [Colors.white.withValues(alpha: 0.05), Colors.white.withValues(alpha: 0.02)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: streak > 0 ? [
                    BoxShadow(
                      color: Colors.orange.withValues(alpha: 0.3),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    )
                  ] : [],
                  border: Border.all(
                    color: streak > 0 
                        ? Colors.orangeAccent.withValues(alpha: 0.5) 
                        : Colors.white.withValues(alpha: 0.05),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: streak > 0 ? 0.2 : 0.05),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.local_fire_department_rounded,
                        color: streak > 0 ? Colors.white : Colors.white24,
                        size: 26,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            streak > 0 
                                ? 'Chuỗi Điểm Danh: $streak Ngày! 🔥' 
                                : 'Bắt đầu chuỗi điểm danh 📅',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 14.5,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            streak > 0 
                                ? 'Cực tốt! Duy trì điểm danh mỗi ngày để giữ ngọn lửa thói quen tốt.' 
                                : 'Hãy điểm danh hôm nay để kích hoạt chuỗi ngày thói quen tốt.',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.8),
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],

            Row(
              children: [
                Text(
                  'Đã điểm danh: ${filteredDates.length} ngày',
                  style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(
              child: ListView.builder(
                controller: scrollController,
                physics: const BouncingScrollPhysics(),
                itemCount: filteredDates.length,
                itemBuilder: (context, index) {
                  final dateStr = filteredDates[index];
                  String formattedDate = dateStr;
                  try {
                    final date = DateTime.parse(dateStr);
                    formattedDate = '${date.day}/${date.month}/${date.year}';
                  } catch (_) {}

                  return Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.04),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.05),
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: AppTheme.neonBlue.withValues(alpha: 0.1),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.calendar_today_rounded,
                            color: AppTheme.neonBlue,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Điểm Danh Hằng Ngày',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14.5,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Ngày ghi nhận: $formattedDate',
                                style: const TextStyle(
                                  color: AppTheme.textSecondary,
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: AppTheme.neonGreen.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Text(
                            'Hoàn thành',
                            style: TextStyle(
                              color: AppTheme.neonGreen,
                              fontWeight: FontWeight.bold,
                              fontSize: 10,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.fitness_center_rounded, size: 48, color: Colors.white24),
          const SizedBox(height: 12),
          Text(
            _selectedDate == null
                ? 'Chưa có dữ liệu!'
                : 'Không tìm thấy dữ liệu trong ngày này!',
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppTheme.textSecondary),
          ),
        ],
      ),
    );
  }
}