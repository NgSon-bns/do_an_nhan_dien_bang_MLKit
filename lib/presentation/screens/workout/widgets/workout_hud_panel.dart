import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:demo/core/theme/app_theme.dart';
import 'package:demo/domain/exercise.dart';
import 'package:demo/domain/workout_session.dart';

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
  final bool isWorkoutStarted;

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
    this.isWorkoutStarted = false,
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

    
    _tts.setLanguage("vi-VN");
    _tts.setSpeechRate(0.7);
    _tts.setVolume(1.0);

    
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

    
    final isCountdown = message == 'Chuẩn bị' ||
        message == '3' ||
        message == '2' ||
        message == '1' ||
        message == 'Bắt đầu!' ||
        message == 'Đã hủy';

    if (isCountdown) {
      await _tts.stop();
      await _playMessage(message);
      return;
    }

    if (isErrorFeedback) {
      
      if (_lastErrorSpeechTime != null &&
          now.difference(_lastErrorSpeechTime!) < const Duration(seconds: 4)) {
        return;
      }
      _lastErrorSpeechTime = now;
    } else {
      
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

    
    if (!widget.isPostureCorrect) {
      if (widget.feedbackMessage.isNotEmpty) {
        _shakeController.forward(from: 0.0);
        _speak(widget.feedbackMessage, isErrorFeedback: true);
      }
    } else if (widget.feedbackMessage.isNotEmpty && feedbackUpdated) {
      
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

    final isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;

    if (isLandscape) {
      return Stack(
        children: [
          
          Positioned(
            top: 12,
            left: 16,
            right: 272,
            child: Row(
              children: [
                _buildIconButton(Icons.arrow_back, widget.onBackPressed),
                const SizedBox(width: 8),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
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
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.neonGreen,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          
          Positioned(
            top: 12,
            bottom: 12,
            right: 16,
            width: 240,
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: AppTheme.glassDecoration(
                color: Colors.black.withValues(alpha: 0.8),
                borderRadius: 20,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'TRẠNG THÁI',
                          style: TextStyle(
                            color: Colors.grey,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.0,
                          ),
                        ),
                        Row(
                          children: [
                            _buildMiniIconButton(Icons.flip_camera_ios, widget.onToggleCameraPressed),
                            const SizedBox(width: 4),
                            _buildMiniIconButton(Icons.refresh, widget.onResetPressed),
                          ],
                        ),
                      ],
                    ),
                    const Divider(color: Colors.white12, height: 16),

                    if (widget.isWorkoutStarted) ...[
                      
                      Text(
                        isDuration ? 'THỜI GIAN GIỮ' : 'SỐ LẦN ĐÃ TẬP',
                        style: const TextStyle(color: Colors.grey, fontSize: 10, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Text(
                            isDuration ? '${widget.session.activeHoldSeconds}' : '${widget.session.counter}',
                            style: TextStyle(
                              fontSize: 36,
                              fontWeight: FontWeight.w900,
                              color: AppTheme.neonGreen,
                              height: 1.0,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            isDuration ? 'giây' : 'lần',
                            style: const TextStyle(fontSize: 14, color: Colors.grey),
                          ),
                        ],
                      ),
                      const Divider(color: Colors.white12, height: 20),

                      
                      if (!isDuration) ...[
                        _buildTargetInfo(widget.targetCount),
                        const Divider(color: Colors.white12, height: 20),
                      ],

                      
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Thời gian:', style: TextStyle(color: Colors.grey, fontSize: 11)),
                          Text(_formatDuration(widget.session.elapsedSeconds), style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Năng lượng:', style: TextStyle(color: Colors.grey, fontSize: 11)),
                          Text('${widget.session.caloriesBurned.toStringAsFixed(1)} kcal', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ] else ...[
                      
                      const Row(
                        children: [
                          Icon(Icons.info_outline, color: AppTheme.neonGreen, size: 16),
                          SizedBox(width: 6),
                          Text(
                            'HƯỚNG DẪN BẮT ĐẦU',
                            style: TextStyle(
                              color: AppTheme.neonGreen,
                              fontWeight: FontWeight.bold,
                              fontSize: 10,
                              letterSpacing: 0.8,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Vui lòng đứng vào khung chữ nhật trên màn hình. AI sẽ tự động nhận diện góc đứng và kích hoạt đếm ngược.',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 10.5,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),

          
          if (widget.session.feedbackMessage.isNotEmpty)
            Positioned(
              bottom: 12,
              left: 16,
              right: 272,
              child: AnimatedBuilder(
                animation: _shakeController,
                builder: (context, child) => Transform.translate(
                  offset: _getShakeOffset(_shakeController.value),
                  child: child,
                ),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: AppTheme.glassDecoration(
                    color: cardColor,
                    borderRadius: 16,
                  ),
                  child: Row(
                    children: [
                      Icon(cardIcon, color: textColor, size: 20),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          widget.session.feedbackMessage,
                          style: TextStyle(
                            color: textColor,
                            fontWeight: FontWeight.bold,
                            fontSize: 12.5,
                          ),
                        ),
                      ),
                      if (widget.session.isResting && widget.onSkipRestPressed != null) ...[
                        const SizedBox(width: 10),
                        TextButton(
                          onPressed: widget.onSkipRestPressed,
                          style: TextButton.styleFrom(
                            backgroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          child: const Text(
                            'BỎ QUA',
                            style: TextStyle(
                              color: Colors.black,
                              fontWeight: FontWeight.bold,
                              fontSize: 11,
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

    return Stack(
      children: [
        
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

        
        if (widget.isWorkoutStarted)
          Positioned(
            top: 110,
            left: 20,
            right: 20,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: AppTheme.glassDecoration(
                color: Colors.black.withValues(alpha: 0.85),
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
          )
        else
          Positioned(
            top: 110,
            left: 20,
            right: 20,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: AppTheme.glassDecoration(
                color: Colors.black.withValues(alpha: 0.8),
                borderRadius: 16,
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline, color: AppTheme.neonGreen, size: 24),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'HƯỚNG DẪN BẮT ĐẦU',
                          style: TextStyle(
                            color: AppTheme.neonGreen,
                            fontWeight: FontWeight.bold,
                            fontSize: 11,
                            letterSpacing: 1.0,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Vui lòng đứng vào khung chữ nhật trên màn hình và xoay người theo đúng góc camera đã chọn ở phía trên.',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.85),
                            fontSize: 11,
                            height: 1.3,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

        
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

  Widget _buildMiniIconButton(IconData icon, VoidCallback onTap) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white10),
      ),
      child: Icon(icon, color: Colors.white, size: 14),
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
