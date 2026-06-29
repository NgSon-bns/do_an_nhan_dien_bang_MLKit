import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/exercise.dart';
import '../../../models/workout_session.dart';

enum HudStatus { correct, warning, error }

class WorkoutHudPanel extends StatefulWidget {
  final ExerciseDetail exercise;
  final int targetCount;
  final bool noSplit;
  final WorkoutSession session;
  final String feedbackMessage;
  final bool isPostureCorrect;
  final String announcementMessage;
  final VoidCallback onBackPressed;
  final VoidCallback onResetPressed;
  final VoidCallback onToggleCameraPressed;
  final VoidCallback? onSkipRestPressed;

  const WorkoutHudPanel({
    super.key,
    required this.exercise,
    required this.targetCount,
    required this.noSplit,
    required this.session,
    required this.feedbackMessage,
    required this.isPostureCorrect,
    required this.announcementMessage,
    required this.onBackPressed,
    required this.onResetPressed,
    required this.onToggleCameraPressed,
    this.onSkipRestPressed,
  });

  @override
  State<WorkoutHudPanel> createState() => _WorkoutHudPanelState();
}

class _WorkoutHudPanelState extends State<WorkoutHudPanel>
    with SingleTickerProviderStateMixin {
  late AnimationController _shakeController;
  late FlutterTts _tts;
  bool _isSpeaking = false;
  String _lastSpokenMessage = '';
  String? _queuedMessage;
  DateTime? _lastErrorSpeechTime;

  @override
  void initState() {
    super.initState();
    _tts = FlutterTts();

    // Đảm bảo cấu hình TTS ngay khi khởi tạo
    _tts.setLanguage("vi-VN");
    _tts.setSpeechRate(0.7);
    _tts.setVolume(1.0);

    // CỐT LÕI: Đăng ký sự kiện khi TTS đọc xong câu
    _tts.setCompletionHandler(() async {
      _isSpeaking = false;
      if (_queuedMessage != null && _queuedMessage!.isNotEmpty) {
        final message = _queuedMessage;
        _queuedMessage = null;
        await _playMessage(message!);
      }
    });

    _shakeController = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );
  }

  Future<void> _playMessage(String message) async {
    if (message.isEmpty) return;

    _isSpeaking = true;
    _lastSpokenMessage = message;
    await _tts.speak(message);
  }

  Future<void> _speak(String message, {bool isErrorFeedback = false}) async {
    if (message.isEmpty) return;

    final now = DateTime.now();

    if (isErrorFeedback) {
      // Giới hạn thời gian phát cảnh báo sai tư thế: tối thiểu 4 giây giữa các lần phát để không bị lặp liên tục dồn dập
      if (_lastErrorSpeechTime != null &&
          now.difference(_lastErrorSpeechTime!) < const Duration(seconds: 4)) {
        return;
      }
      _lastErrorSpeechTime = now;
    } else {
      // Announcements chỉ phát một lần nếu trùng lặp
      if (_lastSpokenMessage == message) return;
    }

    if (_isSpeaking) {
      _queuedMessage = message;
      return;
    }

    await _playMessage(message);
  }

  @override
  void didUpdateWidget(covariant WorkoutHudPanel oldWidget) {
    super.didUpdateWidget(oldWidget);

    final feedbackUpdated = oldWidget.feedbackMessage != widget.feedbackMessage;

    // Error feedback: phát liên tục khi sai, ngừng khi đúng
    if (!widget.isPostureCorrect) {
      if (widget.feedbackMessage.isNotEmpty) {
        _shakeController.forward(from: 0.0);
        _speak(widget.feedbackMessage, isErrorFeedback: true);
      }
    } else if (widget.feedbackMessage.isNotEmpty && feedbackUpdated) {
      // Detection warning
      if (widget.feedbackMessage.contains('Hiện chưa xác định')) {
        _speak(widget.feedbackMessage, isErrorFeedback: true);
      }
    }

    if (widget.announcementMessage.isNotEmpty &&
        oldWidget.announcementMessage != widget.announcementMessage) {
      _speak(widget.announcementMessage);
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
    if (value < 0.2) {
      offset = value / 0.2 * 10;
    } else if (value < 0.4) {
      offset = (0.4 - value) / 0.2 * -10;
    } else if (value < 0.6) {
      offset = (value - 0.4) / 0.2 * 6;
    } else if (value < 0.8) {
      offset = (0.8 - value) / 0.2 * -6;
    }
    return Offset(offset, 0);
  }

  String _formatDuration(int totalSeconds) {
    final minutes = (totalSeconds ~/ 60).toString().padLeft(2, '0');
    final seconds = (totalSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  HudStatus _getHudStatus() {
    final msg = widget.session.feedbackMessage;
    if (msg.contains('chưa xác định') ||
        msg.contains('thấy rõ') ||
        msg.contains('nhìn thấy') ||
        msg.contains('đứng lùi') ||
        msg.contains('nghiêng người') ||
        msg.contains('Chưa phát hiện') ||
        msg.contains('Không tìm thấy') ||
        msg.contains('Đang nghỉ') ||
        msg.contains('Bắt đầu set') ||
        msg.contains('Chuẩn bị') ||
        msg.contains('quay trở lại') ||
        msg.contains('điều chỉnh')) {
      return HudStatus.warning;
    }
    if (widget.session.isPostureCorrect) {
      return HudStatus.correct;
    }
    return HudStatus.error;
  }

  @override
  Widget build(BuildContext context) {
    final isDuration = widget.exercise.isDurationBased;
    
    final status = _getHudStatus();
    final Color cardColor;
    final IconData cardIcon;
    final Color textColor;

    switch (status) {
      case HudStatus.correct:
        cardColor = AppTheme.neonGreen.withValues(alpha: 0.85);
        cardIcon = Icons.check_circle;
        textColor = Colors.black87;
        break;
      case HudStatus.warning:
        cardColor = Colors.amber.withValues(alpha: 0.85);
        cardIcon = Icons.warning_amber_rounded;
        textColor = Colors.black87;
        break;
      case HudStatus.error:
        cardColor = AppTheme.errorRed.withValues(alpha: 0.85);
        cardIcon = Icons.error_outline;
        textColor = Colors.white;
        break;
    }

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
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  decoration: AppTheme.glassDecoration(
                    color: Colors.black,
                    borderRadius: 12,
                  ),
                  child: Text(
                    widget.exercise.name.toUpperCase(),
                    textAlign: TextAlign.center,
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.neonGreen,
                    ),
                  ),
                ),
              ),
              Row(
                children: [
                  _buildIconButton(
                    Icons.flip_camera_ios,
                    widget.onToggleCameraPressed,
                  ),
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
            decoration: AppTheme.glassDecoration(
              color: Colors.black.withValues(alpha: 0.8),
              borderRadius: 16,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildStatColumn(
                  isDuration ? 'THỜI GIAN GIỮ' : 'SỐ LẦN ĐÃ TẬP',
                  isDuration
                      ? '${widget.session.activeHoldSeconds}'
                      : '${widget.session.counter}',
                  isDuration ? 'giây' : 'lần',
                ),
                if (!isDuration) ...[
                  Container(height: 50, width: 1, color: Colors.white12),
                  Expanded(child: _buildTargetInfo(widget.targetCount)),
                ] else ...[
                  Container(height: 50, width: 1, color: Colors.white12),
                  _buildInfoColumn(),
                ],
              ],
            ),
          ),
        ),

        // 3. KHUNG CẢNH BÁO (Tối ưu với AnimatedBuilder và AnimatedContainer)
        if (widget.session.feedbackMessage.isNotEmpty)
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
                color: cardColor,
                borderRadius: 20,
              ),
              child: Row(
                children: [
                  Icon(
                    cardIcon,
                    color: textColor,
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Text(
                      widget.session.feedbackMessage,
                      style: TextStyle(
                        color: textColor,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  if (widget.session.isResting && widget.onSkipRestPressed != null) ...[
                    const SizedBox(width: 12),
                    TextButton(
                      onPressed: widget.onSkipRestPressed,
                      style: TextButton.styleFrom(
                        backgroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: const Text(
                        'BỎ QUA',
                        style: TextStyle(
                          color: Colors.black,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
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
      decoration: AppTheme.glassDecoration(
        color: Colors.black,
        borderRadius: 12,
      ),
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
          Text(
            value,
            style: const TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.w900,
              color: Colors.white,
            ),
          ),
          const SizedBox(width: 4),
          Text(unit, style: const TextStyle(fontSize: 12, color: Colors.grey)),
        ],
      ),
    ],
  );

  Widget _buildInfoColumn() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        '⏱ ${_formatDuration(widget.session.elapsedSeconds)}',
        style: const TextStyle(color: Colors.white),
      ),
      Text(
        '🔥 ${widget.session.caloriesBurned.toStringAsFixed(1)} kcal',
        style: const TextStyle(color: Colors.white),
      ),
    ],
  );

  Widget _buildTargetInfo(int targetCount) {
    final plan = widget.noSplit
        ? [targetCount]
        : ExerciseDetail.computeSetPlan(targetCount);
    final planText = widget.noSplit
        ? 'Không chia rep — 1 set ($targetCount)'
        : plan.isNotEmpty
        ? '${plan.length} set (${plan.map((value) => '$value').join(' + ')})'
        : 'Không có kế hoạch set';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Mục tiêu: $targetCount lần',
          style: const TextStyle(color: Colors.white, fontSize: 12),
        ),
        const SizedBox(height: 4),
        Text(
          'Kế hoạch set: $planText',
          style: const TextStyle(color: AppTheme.textSecondary, fontSize: 10),
        ),
      ],
    );
  }
}
