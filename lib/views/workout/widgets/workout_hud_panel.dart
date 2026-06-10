import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // Import để sử dụng HapticFeedback
import 'package:flutter_tts/flutter_tts.dart';
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
  late FlutterTts _tts;
  bool _isSpeakingError = false;

  @override
  void initState() {
    super.initState();
    _tts = FlutterTts();
    
    // Đảm bảo cấu hình TTS ngay khi khởi tạo
    _tts.setLanguage("vi-VN");
    _tts.setSpeechRate(0.7);
    _tts.setVolume(1.0);

    // CỐT LÕI: Đăng ký sự kiện khi TTS đọc xong câu
    _tts.setCompletionHandler(() {
      _isSpeakingError = false; 
    });

    _shakeController = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );
  }

  Future<void> _speakError(String message) async {
    // Nếu đang nói hoặc message trống, thoát ngay
    if (_isSpeakingError || message.isEmpty) return;

    _isSpeakingError = true; // Khóa lại
    
    await _tts.stop(); // Dừng âm thanh cũ
    await _tts.speak(message); // Phát âm thanh mới
    // KHÔNG đặt _isSpeakingError = false ở đây nữa
  }

  @override
  void didUpdateWidget(covariant WorkoutHudPanel oldWidget) {
  super.didUpdateWidget(oldWidget);

  // Chỉ kích hoạt khi trạng thái thay đổi từ ĐÚNG -> SAI
  if (!widget.session.isPostureCorrect ) {
    _shakeController.forward(from: 0.0);
    HapticFeedback.heavyImpact();
    _speakError(widget.session.feedbackMessage);
  }
}

  @override
  void dispose() {
    _tts.stop();
    _shakeController.dispose();
    super.dispose();
  }

  Offset _getShakeOffset(double value) {
    double offset = 0.0;
    if (value < 0.2) offset = value / 0.2 * 10;
    else if (value < 0.4) offset = (0.4 - value) / 0.2 * -10;
    else if (value < 0.6) offset = (value - 0.4) / 0.2 * 6;
    else if (value < 0.8) offset = (0.8 - value) / 0.2 * -6;
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
        // 1. THANH ĐIỀU HƯỚNG
        Positioned(
          top: 40,
          left: 20,
          right: 20,
          child: Row(
            children: [
              _buildIconButton(Icons.arrow_back, widget.onBackPressed),
              Expanded(
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: AppTheme.glassDecoration(color: Colors.black, borderRadius: 12),
                  child: Text(
                    widget.exercise.name.toUpperCase(),
                    textAlign: TextAlign.center,
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppTheme.neonGreen),
                  ),
                ),
              ),
              Row(
                children: [
                  _buildIconButton(Icons.flip_camera_ios, widget.onToggleCameraPressed),
                  const SizedBox(width: 8),
                  _buildIconButton(Icons.refresh, widget.onResetPressed),
                ],
              ),
            ],
          ),
        ),

        // 2. KHUNG CHỈ SỐ
        Positioned(
          top: 110,
          left: 20,
          right: 20,
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: AppTheme.glassDecoration(color: Colors.black.withValues(alpha: 0.8), borderRadius: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildStatColumn(
                  isDuration ? 'THỜI GIAN GIỮ' : 'SỐ LẦN ĐÃ TẬP',
                  isDuration ? '${widget.session.activeHoldSeconds}' : '${widget.session.counter}',
                  isDuration ? 'giây' : 'lần',
                ),
                Container(height: 50, width: 1, color: Colors.white12),
                _buildInfoColumn(),
              ],
            ),
          ),
        ),

        // 3. KHUNG CẢNH BÁO (Tối ưu với AnimatedBuilder và AnimatedContainer)
        Positioned(
          bottom: 40,
          left: 20,
          right: 20,
          child: AnimatedBuilder(
            animation: _shakeController,
            builder: (context, child) => Transform.translate(
              offset: _getShakeOffset(_shakeController.value),
              child: child,
            ),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              padding: const EdgeInsets.all(16),
              decoration: AppTheme.glassDecoration(
                color: widget.session.isPostureCorrect ? Colors.black.withValues(alpha: 0.8) : AppTheme.errorRed.withValues(alpha: 0.85),
                borderRadius: 20,
              ),
              child: Row(
                children: [
                  Icon(widget.session.isPostureCorrect ? Icons.check_circle : Icons.warning_amber_rounded, color: Colors.white),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Text(widget.session.feedbackMessage, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  // --- Các hàm tiện ích để code gọn hơn ---
  Widget _buildIconButton(IconData icon, VoidCallback onTap) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: AppTheme.glassDecoration(color: Colors.black, borderRadius: 12),
          child: Icon(icon, color: Colors.white, size: 20),
        ),
      );

  Widget _buildStatColumn(String label, String value, String unit) => Column(
        children: [
          Text(label, style: const TextStyle(fontSize: 10, color: Colors.grey)),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(value, style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w900, color: Colors.white)),
              const SizedBox(width: 4),
              Text(unit, style: const TextStyle(fontSize: 12, color: Colors.grey)),
            ],
          )
        ],
      );

  Widget _buildInfoColumn() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('⏱ ${_formatDuration(widget.session.elapsedSeconds)}', style: const TextStyle(color: Colors.white)),
          Text('🔥 ${widget.session.caloriesBurned.toStringAsFixed(1)} kcal', style: const TextStyle(color: Colors.white)),
        ],
      );
}