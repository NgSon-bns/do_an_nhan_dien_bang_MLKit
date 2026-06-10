import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/exercise.dart';
import '../../../models/workout_session.dart';

class WorkoutHudPanel extends StatefulWidget {
  final ExerciseDetail exercise;
  final WorkoutSession session;
  final VoidCallback onBackPressed;
  final VoidCallback onResetPressed;
  final VoidCallback onToggleCameraPressed;

  const WorkoutHudPanel({
    super.key,
    required this.exercise,
    required this.session,
    required this.onBackPressed,
    required this.onResetPressed,
    required this.onToggleCameraPressed,
  });

  @override
  State<WorkoutHudPanel> createState() => _WorkoutHudPanelState();
}

class _WorkoutHudPanelState extends State<WorkoutHudPanel>
    with SingleTickerProviderStateMixin {
  late AnimationController _shakeController;

  @override
  void initState() {
    super.initState();
    _shakeController = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );
  }

  @override
  void didUpdateWidget(covariant WorkoutHudPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Nếu tư thế vừa đổi sang sai, kích hoạt rung lắc phản hồi
    if (!widget.session.isPostureCorrect && oldWidget.session.isPostureCorrect) {
      _shakeController.forward(from: 0.0);
    }
  }

  @override
  void dispose() {
    _shakeController.dispose();
    super.dispose();
  }

  // Định nghĩa hàm rung lắc phụ trợ cho hộp thoại cảnh báo sai tư thế
  Offset _getShakeOffset(double value) {
    // Tạo 3 nhịp lắc trái phải
    double offset = 0.0;
    if (value < 0.2) {
      offset = value / 0.2 * 10;
    } else if (value < 0.4) {
      offset = (0.4 - value) / 0.2 * -10;
    } else if (value < 0.6) {
      offset = (value - 0.4) / 0.2 * 6;
    } else if (value < 0.8) {
      offset = (0.8 - value) / 0.2 * -6;
    } else {
      offset = 0;
    }
    return Offset(offset, 0);
  }

  String _formatDuration(int totalSeconds) {
    final minutes = (totalSeconds ~/ 60).toString().padLeft(2, '0');
    final seconds = (totalSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final isDuration = widget.exercise.isDurationBased;

    return Stack(
      children: [
        // 1. THANH ĐIỀU HƯỚNG TRÊN CÙNG
        Positioned(
          top: 40,
          left: 20,
          right: 20,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Nút quay về
              GestureDetector(
                onTap: widget.onBackPressed,
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: AppTheme.glassDecoration(
                    color: Colors.black,
                    borderRadius: 12,
                  ),
                  child: const Icon(Icons.arrow_back, color: Colors.white),
                ),
              ),
              
              // Tiêu đề bài tập ở giữa
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: AppTheme.glassDecoration(
                  color: Colors.black,
                  borderRadius: 12,
                ),
                child: Text(
                  widget.exercise.name.toUpperCase(),
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.neonGreen,
                    letterSpacing: 1.0,
                  ),
                ),
              ),

              // Nhóm nút chức năng bên phải: Reset + Đảo Camera
              Row(
                children: [
                  GestureDetector(
                    onTap: widget.onToggleCameraPressed,
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: AppTheme.glassDecoration(
                        color: Colors.black,
                        borderRadius: 12,
                      ),
                      child: const Icon(Icons.flip_camera_ios, color: Colors.white),
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: widget.onResetPressed,
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: AppTheme.glassDecoration(
                        color: Colors.black,
                        borderRadius: 12,
                      ),
                      child: const Icon(Icons.refresh, color: Colors.white),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),

        // 2. KHUNG HIỂN THỊ CHỈ SỐ Ở GIỮA PHÍA TRÊN
        Positioned(
          top: 110,
          left: 20,
          right: 20,
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: AppTheme.glassDecoration(
              color: Colors.black.withValues(alpha: 0.8),
              borderRadius: 16,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                // Chỉ số 1: Số lần (Reps) hoặc Thời gian giữ (Hold)
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      isDuration ? 'THỜI GIAN GIỮ' : 'SỐ LẦN ĐÃ TẬP',
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppTheme.textSecondary,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text(
                          isDuration
                              ? '${widget.session.activeHoldSeconds}'
                              : '${widget.session.counter}',
                          style: const TextStyle(
                            fontSize: 40,
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          isDuration ? 'giây' : 'lần',
                          style: const TextStyle(
                            fontSize: 14,
                            color: AppTheme.textSecondary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      isDuration
                          ? 'Mục tiêu: ${widget.exercise.targetValue}s'
                          : 'Mục tiêu: ${widget.exercise.targetValue} lần',
                      style: const TextStyle(
                        fontSize: 11,
                        color: Colors.grey,
                      ),
                    ),
                  ],
                ),
                
                // Vạch ngăn cách dọc
                Container(
                  height: 60,
                  width: 1,
                  color: Colors.white12,
                ),

                // Chỉ số 2: Tổng thời gian tập & Calo tiêu hao
                Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.access_time, size: 14, color: AppTheme.neonBlue),
                        const SizedBox(width: 6),
                        Text(
                          _formatDuration(widget.session.elapsedSeconds),
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Icon(Icons.local_fire_department, size: 14, color: Colors.orange),
                        const SizedBox(width: 6),
                        Text(
                          '${widget.session.caloriesBurned.toStringAsFixed(1)} kcal',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(Icons.warning_amber_rounded, size: 12, color: AppTheme.errorRed),
                        const SizedBox(width: 4),
                        Text(
                          'Số lỗi: ${widget.session.incorrectPostureCount}',
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppTheme.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),

        // 3. KHUNG CẢNH BÁO TƯ THẾ DƯỚI ĐÁY MÀN HÌNH
        Positioned(
          bottom: 40,
          left: 20,
          right: 20,
          child: AnimatedBuilder(
            animation: _shakeController,
            builder: (context, child) {
              final isCorrect = widget.session.isPostureCorrect;
              return Transform.translate(
                offset: _getShakeOffset(_shakeController.value),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  decoration: AppTheme.glassDecoration(
                    color: isCorrect 
                        ? Colors.black.withValues(alpha: 0.8)
                        : AppTheme.errorRed.withValues(alpha: 0.85),
                    borderRadius: 20,
                    borderWidth: isCorrect ? 1.0 : 2.0,
                  ),
                  child: Row(
                    children: [
                      // Icon chỉ thị
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: isCorrect
                              ? AppTheme.neonGreen.withValues(alpha: 0.2)
                              : Colors.white.withValues(alpha: 0.25),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          isCorrect ? Icons.check_circle_outline : Icons.warning_amber_rounded,
                          color: isCorrect ? AppTheme.neonGreen : Colors.white,
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 16),
                      // Text hướng dẫn sửa tư thế
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              isCorrect ? 'TƯ THẾ CHUẨN' : 'PHÁT HIỆN SAI TƯ THẾ',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: isCorrect ? AppTheme.neonGreen : Colors.white70,
                                letterSpacing: 0.8,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              widget.session.feedbackMessage,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: isCorrect ? FontWeight.w500 : FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
