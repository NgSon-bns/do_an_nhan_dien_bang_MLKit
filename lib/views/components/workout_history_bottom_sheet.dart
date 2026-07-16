import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../../services/database_service.dart';

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
        return FutureBuilder<List<Map<String, dynamic>>>(
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
                            'Nhật Ký Tập Luyện',
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
                              ? 'Tất cả lịch sử'
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
                                _selectedDate = null; // BỎ CHỌN: Hiển thị lại toàn bộ
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
                                _selectedDate = DateTime.now(); // Xem nhanh hôm nay
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

                  // Xử lý hiển thị danh sách lịch sử
                  Expanded(
                    child: _buildHistoryContent(snapshot, scrollController),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildHistoryContent(
    AsyncSnapshot<List<Map<String, dynamic>>> snapshot,
    ScrollController scrollController,
  ) {
    if (snapshot.connectionState == ConnectionState.waiting) {
      return const Center(
        child: CircularProgressIndicator(color: AppTheme.neonGreen),
      );
    }

    if (snapshot.hasError || !snapshot.hasData || snapshot.data!.isEmpty) {
      return _buildEmptyState();
    }

    final rawHistoryList = snapshot.data!;

    // Thực hiện bộ lọc
    final historyList = rawHistoryList.where((workout) {
      // 1. Lọc bỏ Check_in
      final String rawExerciseName = (workout['exercise_id'] ?? workout['exercise_type'] ?? '').toString();
      final lowercaseName = rawExerciseName.toLowerCase();
      if (lowercaseName.contains('check_in') || lowercaseName.contains('checkin') || lowercaseName.contains('check-in')) {
        return false;
      }

      // 2. Lọc đúng ngày được chọn (nếu có chọn)
      if (_selectedDate != null) {
        if (workout['created_at'] == null) return false;
        try {
          final date = DateTime.parse(workout['created_at'].toString()).toLocal();
          return _isSameDay(date, _selectedDate!);
        } catch (_) {
          return false;
        }
      }

      // Nếu không có ngày nào được chọn (_selectedDate == null) -> giữ lại hết
      return true;
    }).toList();

    // Nếu không có hoạt động nào sau khi lọc
    if (historyList.isEmpty) {
      return _buildEmptyState();
    }

    // Tính tổng calo tiêu hao trong danh sách hiện tại
    double totalCalories = 0;
    for (var workout in historyList) {
      totalCalories += ((workout['calories_burned'] ?? 0) as num).toDouble();
    }

    return Column(
      children: [
        // Widget hiển thị Tổng kết
        Row(
          children: [
            Text(
              'Đã tập: ${historyList.length} bài',
              style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13),
            ),
            const Spacer(),
            Text(
              'Tổng tiêu hao: ${totalCalories.toStringAsFixed(1)} kcal',
              style: const TextStyle(
                color: Colors.orangeAccent,
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // Danh sách hiển thị chính
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

              // Định dạng ngày giờ hiển thị
              String formattedDate = '';
              if (workout['created_at'] != null) {
                try {
                  final date = DateTime.parse(workout['created_at'].toString()).toLocal();
                  // Nếu là hiển thị tất cả -> hiển thị cả ngày, nếu đã lọc theo ngày -> chỉ hiện giờ tập cho thoáng
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
                        color: AppTheme.neonGreen.withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.check,
                        color: AppTheme.neonGreen,
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
                          reps > 0 ?  '$reps lần':'$duration giây' ,
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

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.fitness_center_rounded, size: 48, color: Colors.white24),
          const SizedBox(height: 12),
          Text(
            _selectedDate == null
                ? 'Chưa có lịch sử tập luyện nào!'
                : 'Không tìm thấy lịch sử tập luyện trong ngày này!',
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppTheme.textSecondary),
          ),
        ],
      ),
    );
  }
}