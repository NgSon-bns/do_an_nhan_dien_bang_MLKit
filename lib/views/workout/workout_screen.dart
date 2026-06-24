import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show Supabase;

import '../../core/theme/app_theme.dart';
import '../../models/exercise.dart';
import '../../models/workout_session.dart';
import '../../services/pose_analysis/base_pose_evaluator.dart';
import '../../services/pose_analysis/evaluator_factory.dart';
import '../../services/pose_detector_service.dart';
import '../../services/database_service.dart';
import 'widgets/camera_stream_view.dart';
import 'widgets/workout_hud_panel.dart';

class WorkoutScreen extends StatefulWidget {
  final ExerciseDetail exercise;
  final int targetCount;
  final bool noSplit;
  final List<CameraDescription> cameras;

  const WorkoutScreen({
    super.key,
    required this.exercise,
    required this.targetCount,
    required this.noSplit,
    required this.cameras,
  });

  @override
  State<WorkoutScreen> createState() => _WorkoutScreenState();
}

class _WorkoutScreenState extends State<WorkoutScreen> {
  late CameraController _cameraController;
  late PoseDetectorService _poseDetectorService;

  int _currentCameraIndex = 0;
  bool _isCameraInitialized = false;
  bool _isProcessing = false;
  bool _isPoseDetected = false;

  // Đối tượng lưu trữ trạng thái buổi tập
  final WorkoutSession _session = WorkoutSession();
  late final List<int> _setPlan;
  int _currentSetIndex = 0;
  int _currentSetCount = 0;
  Timer? _workoutTimer;

  // Dữ liệu khung xương
  List<Pose> _poses = [];

  late BasePoseEvaluator _evaluator;

  // Cờ hiệu kiểm soát lỗi tư thế để tránh cộng dồn lỗi liên tục theo từng khung hình (30fps)
  bool _wasPostureCorrectLastFrame = true;

  @override
  void initState() {
    super.initState();
    _poseDetectorService = PoseDetectorService();
    _poseDetectorService.initialize();
    _evaluator = EvaluatorFactory.create(widget.exercise.type);
    _setPlan = widget.noSplit
        ? [widget.targetCount]
        : ExerciseDetail.computeSetPlan(widget.targetCount);

    // Thường ưu tiên camera trước (Selfie) cho tập luyện nếu có
    _findSelfieCamera();
    _initializeCamera();
    _startTimer();
  }

  void _findSelfieCamera() {
    for (int i = 0; i < widget.cameras.length; i++) {
      if (widget.cameras[i].lensDirection == CameraLensDirection.front) {
        _currentCameraIndex = i;
        return;
      }
    }
    _currentCameraIndex = 0; // Mặc định dùng camera đầu tiên
  }

  Future<void> _initializeCamera() async {
    setState(() {
      _isCameraInitialized = false;
    });

    _cameraController = CameraController(
      widget.cameras[_currentCameraIndex],
      ResolutionPreset.medium,
      enableAudio: false,
      imageFormatGroup: Platform.isAndroid
          ? ImageFormatGroup.nv21
          : ImageFormatGroup.bgra8888,
    );

    try {
      await _cameraController.initialize();
      if (!mounted) return;

      // Bắt đầu stream hình ảnh để AI phân tích
      await _cameraController.startImageStream((cameraImage) {
        if (!_isProcessing && mounted) {
          _isProcessing = true;
          _processImage(cameraImage);
        }
      });

      setState(() {
        _isCameraInitialized = true;
      });
    } catch (e) {
      debugPrint('Lỗi khởi tạo camera: $e');
    }
  }

  /// Bộ đếm thời gian tự động mỗi giây
  void _startTimer() {
    _workoutTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      setState(() {
        _session.elapsedSeconds++;

        // Dành riêng cho Plank: Chỉ tích lũy giây tập khi đúng tư thế
        if (widget.exercise.type == ExerciseType.plank) {
          if (_isPoseDetected && _session.isPostureCorrect) {
            _session.activeHoldSeconds++;
          }
        }

        if (_session.isResting) {
          _session.restSecondsLeft = (_session.restSecondsLeft - 1).clamp(
            0,
            30,
          );
          _session.feedbackMessage =
              'Đang nghỉ ${_session.restSecondsLeft}s. Chuẩn bị set tiếp theo.';

          if (_session.restSecondsLeft == 0) {
            _session.isResting = false;
            _session.announcementMessage =
                'Kết thúc nghỉ. Bắt đầu set tiếp theo.';
            _session.feedbackMessage = 'Bắt đầu set tiếp theo!';
          }
        }

        // Cập nhật calo dựa trên chỉ số bài tập
        _session.updateCalories(
          widget.exercise.caloriesPerMin,
          isDurationBased: widget.exercise.isDurationBased,
        );
      });
    });
  }

  /// Đảo camera trước/sau
  Future<void> _toggleCamera() async {
    if (widget.cameras.length < 2) return;
    setState(() {
      _isCameraInitialized = false;
    });
    // Đóng camera hiện tại
    await _cameraController.stopImageStream();
    await _cameraController.dispose();

    _currentCameraIndex = (_currentCameraIndex + 1) % widget.cameras.length;
    _initializeCamera();
  }

  /// Reset bộ đếm lần tập và thời gian
  void _resetWorkout() {
    _evaluator.reset();
    setState(() {
      _session.reset();
      _currentSetIndex = 0;
      _currentSetCount = 0;
      _poses.clear();
      _isPoseDetected = false;
      _wasPostureCorrectLastFrame = true;
    });
  }

  /// Phân tích hình ảnh camera bằng AI và chạy thuật toán nhận diện
  Future<void> _processImage(CameraImage image) async {
    if (_session.isResting) {
      if (mounted) {
        setState(() {
          _poses.clear();
          _isPoseDetected = false;
        });
      }
      _isProcessing = false;
      return;
    }

    final poses = await _poseDetectorService.processCameraImage(
      image,
      _cameraController,
    );

    if (!mounted) {
      _isProcessing = false;
      return;
    }

    bool hasFullBody = false;
    if (poses.isNotEmpty) {
      hasFullBody = _checkFullBodyVisibility(poses.first, widget.exercise.type);
    }

    setState(() {
      _poses = poses;
      _isPoseDetected = poses.isNotEmpty;
    });

    if (poses.isNotEmpty) {
      if (hasFullBody) {
        if (_session.isResting) {
          setState(() {
            _session.feedbackMessage =
                'Đang nghỉ ${_session.restSecondsLeft}s. Chuẩn bị cho set tiếp theo.';
          });
        } else {
          _analyzePose(poses.first);
        }
      } else {
        _evaluator
            .reset(); // Reset trạng thái chuyển động khi mất dấu toàn thân
        setState(() {
          _session.isPostureCorrect = true; // Trạng thái chờ/bình thường
          _session.feedbackMessage =
              'Hiện chưa xác định được người trong khung hình.';
        });
      }
    } else {
      _evaluator.reset(); // Reset trạng thái khi không phát hiện thấy người
      // Khi không nhận diện được người, đặt lại các phản hồi cơ bản
      setState(() {
        _session.isPostureCorrect = true;
        _session.feedbackMessage =
            'Hiện chưa xác định được người trong khung hình.';
      });
    }

    _isProcessing = false;
  }

  /// Thuật toán chính phân tích góc xương và kiểm tra tư thế
  void _analyzePose(Pose pose) {
    final result = _evaluator.evaluate(pose);

    // Cập nhật số lần lỗi tư thế khi chuyển đổi trạng thái từ Đúng sang Sai
    if (!result.isPostureCorrect && _wasPostureCorrectLastFrame) {
      _session.incorrectPostureCount++;
    }

    if (result.shouldCountRep) {
      _session.counter++;
      _currentSetCount++;
      final currentSetTarget = _setPlan[_currentSetIndex];
      if (_currentSetCount >= currentSetTarget) {
        if (_currentSetIndex < _setPlan.length - 1) {
          _currentSetIndex++;
          _currentSetCount = 0;
          _session.isResting = true;
          _session.restSecondsLeft = 30;
          _session.announcementMessage =
              'Nghỉ 30 giây. Chuẩn bị cho set tiếp theo.';
          _session.feedbackMessage =
              'Đang nghỉ 30s. Set tiếp theo sẽ bắt đầu sau.';
        } else {
          _session.feedbackMessage =
              'Hoàn thành bài tập! Chúc mừng bạn đã hoàn tất.';
          _session.announcementMessage =
              'Bạn đã hoàn thành bài tập. Nghỉ ngơi và tận hưởng thành quả!';
        }
      }
    }

    // Cập nhật trạng thái buổi tập
    setState(() {
      _session.isPostureCorrect = result.isPostureCorrect;
      if (!_session.isResting) {
        _session.feedbackMessage = result.feedbackMessage;
      }
    });

    _wasPostureCorrectLastFrame = result.isPostureCorrect;
  }

  /// Thuật toán kiểm tra toàn thân người hoàn chỉnh trước khi nhận diện (Độ tin cậy >= 0.70)
  bool _checkFullBodyVisibility(Pose pose, ExerciseType type) {
    const double standardConfidence = 0.75;
    const double strictConfidence = 0.82;

    bool isJointVisible(PoseLandmark? landmark, double threshold) {
      return landmark != null && landmark.likelihood >= threshold;
    }

    // 1. Đối với Squat, Jumping Jack và Walking Lunge (bắt buộc trực diện, đủ 2 bên trái & phải)
    if (type == ExerciseType.squat || type == ExerciseType.jumpingJack || type == ExerciseType.walkingLunge) {
      final standardJoints = [
        PoseLandmarkType.leftShoulder,
        PoseLandmarkType.rightShoulder,
        PoseLandmarkType.leftHip,
        PoseLandmarkType.rightHip,
        if (type == ExerciseType.jumpingJack) ...[
          PoseLandmarkType.leftElbow,
          PoseLandmarkType.rightElbow,
          PoseLandmarkType.leftWrist,
          PoseLandmarkType.rightWrist,
        ],
      ];

      final strictJoints = [
        PoseLandmarkType.leftKnee,
        PoseLandmarkType.rightKnee,
        PoseLandmarkType.leftAnkle,
        PoseLandmarkType.rightAnkle,
      ];

      for (final joint in standardJoints) {
        if (!isJointVisible(pose.landmarks[joint], standardConfidence)) {
          return false;
        }
      }

      for (final joint in strictJoints) {
        if (!isJointVisible(pose.landmarks[joint], strictConfidence)) {
          return false;
        }
      }

      return true;
    }

    // 2. Đối với Push-up, Plank (bài tập nghiêng hoặc bán nghiêng)
    // Chỉ yêu cầu ít nhất một bên (Trái hoặc Phải) hiển thị đầy đủ khớp
    final leftSideStandard = [
      PoseLandmarkType.leftShoulder,
      PoseLandmarkType.leftHip,
      if (type == ExerciseType.pushUp || type == ExerciseType.plank) ...[
        PoseLandmarkType.leftElbow,
        PoseLandmarkType.leftWrist,
      ],
    ];
    final leftSideStrict = [
      PoseLandmarkType.leftKnee,
      PoseLandmarkType.leftAnkle,
    ];

    final rightSideStandard = [
      PoseLandmarkType.rightShoulder,
      PoseLandmarkType.rightHip,
      if (type == ExerciseType.pushUp || type == ExerciseType.plank) ...[
        PoseLandmarkType.rightElbow,
        PoseLandmarkType.rightWrist,
      ],
    ];
    final rightSideStrict = [
      PoseLandmarkType.rightKnee,
      PoseLandmarkType.rightAnkle,
    ];

    bool leftSideVisible = true;
    for (final joint in leftSideStandard) {
      if (!isJointVisible(pose.landmarks[joint], standardConfidence)) {
        leftSideVisible = false;
        break;
      }
    }
    if (leftSideVisible) {
      for (final joint in leftSideStrict) {
        if (!isJointVisible(pose.landmarks[joint], strictConfidence)) {
          leftSideVisible = false;
          break;
        }
      }
    }

    bool rightSideVisible = true;
    for (final joint in rightSideStandard) {
      if (!isJointVisible(pose.landmarks[joint], standardConfidence)) {
        rightSideVisible = false;
        break;
      }
    }
    if (rightSideVisible) {
      for (final joint in rightSideStrict) {
        if (!isJointVisible(pose.landmarks[joint], strictConfidence)) {
          rightSideVisible = false;
          break;
        }
      }
    }

    return leftSideVisible || rightSideVisible;
  }

  @override
  void dispose() {
    _workoutTimer?.cancel();
    _cameraController.dispose();
    _poseDetectorService.close();
    super.dispose();
  }

  bool get _isSupabaseInitialized {
    try {
      Supabase.instance.client;
      return true;
    } catch (_) {
      return false;
    }
  }

  Widget _buildDialogStatItem(
    IconData icon,
    String label,
    String value,
    Color color,
  ) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(height: 6),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 13,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(color: AppTheme.textSecondary, fontSize: 10),
        ),
      ],
    );
  }

  Future<bool> _onBackPressed() async {
    // Tạm dừng timer khi hiện dialog
    _workoutTimer?.cancel();

    final isOffline = !_isSupabaseInitialized;
    final isDuration = widget.exercise.isDurationBased;
    final scoreValue = isDuration
        ? _session.activeHoldSeconds
        : _session.counter;
    final scoreUnit = isDuration ? 'giây' : 'lần';

    bool? result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.cardBackground,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Center(
          child: Text(
            'Kết quả tập luyện'.toUpperCase(),
            style: const TextStyle(
              color: AppTheme.neonGreen,
              fontWeight: FontWeight.bold,
              fontSize: 16,
              letterSpacing: 1.0,
            ),
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Divider(color: Colors.white12),
            const SizedBox(height: 16),

            Text(
              '$scoreValue $scoreUnit',
              style: const TextStyle(
                fontSize: 36,
                fontWeight: FontWeight.w900,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 16),

            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildDialogStatItem(
                  Icons.local_fire_department,
                  'Calo',
                  '${_session.caloriesBurned.toStringAsFixed(1)} kcal',
                  Colors.orange,
                ),
                _buildDialogStatItem(
                  Icons.access_time,
                  'Thời gian',
                  '${_session.elapsedSeconds}s',
                  AppTheme.neonBlue,
                ),
                _buildDialogStatItem(
                  Icons.warning_amber_rounded,
                  'Lỗi',
                  '${_session.incorrectPostureCount}',
                  AppTheme.errorRed,
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Divider(color: Colors.white12),
            const SizedBox(height: 8),
            Text(
              isOffline
                  ? 'Ứng dụng chạy ở chế độ Offline. Kết quả sẽ không được lưu lên Cloud.'
                  : 'Kết quả sẽ được đồng bộ trực tuyến lên tài khoản của bạn.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 12,
                color: AppTheme.textSecondary,
              ),
            ),
          ],
        ),
        actionsAlignment: MainAxisAlignment.spaceAround,
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false), // Thoát không lưu
            child: const Text(
              'Thoát',
              style: TextStyle(
                color: AppTheme.errorRed,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          TextButton(
            onPressed: () {
              _startTimer(); // Chạy lại timer
              Navigator.pop(context, null); // Hủy
            },
            child: const Text('Tập tiếp', style: TextStyle(color: Colors.grey)),
          ),
          if (!isOffline)
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true), // Lưu & Thoát
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.neonGreen,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: const Text(
                'Lưu & Thoát',
                style: TextStyle(
                  color: Colors.black,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
        ],
      ),
    );

    if (result == null) {
      return false; // Ở lại màn hình
    }

    if (result == true && !isOffline) {
      if (!mounted) return false;
      // Hiện loading spinner
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(
          child: CircularProgressIndicator(color: AppTheme.neonGreen),
        ),
      );

      try {
        await DatabaseService().saveWorkoutResult(
          exerciseType: widget.exercise.type.name,
          repsCount: _session.counter,
          durationSeconds: _session.elapsedSeconds,
          caloriesBurned: _session.caloriesBurned,
          incorrectPostures: _session.incorrectPostureCount,
        );
      } catch (e) {
        debugPrint('Lỗi lưu kết quả: $e');
      }

      if (!mounted) return true;
      Navigator.pop(context); // Đóng loading spinner
    }

    return true; // Thoát màn hình
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final shouldPop = await _onBackPressed();
        if (shouldPop && context.mounted) {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        body: !_isCameraInitialized
            ? const Center(
                child: CircularProgressIndicator(color: AppTheme.neonGreen),
              )
            : Stack(
                fit: StackFit.expand,
                children: [
                  // 1. Luồng video từ Camera
                  CameraStreamView(controller: _cameraController),

                  // 4. Bảng HUD hiển thị thông số và cảnh báo
                  Positioned.fill(
                    child: WorkoutHudPanel(
                      exercise: widget.exercise,
                      targetCount: widget.targetCount,
                      noSplit: widget.noSplit,
                      session: _session,
                      feedbackMessage: _session.feedbackMessage,
                      isPostureCorrect: _session.isPostureCorrect,
                      announcementMessage: _session.announcementMessage,
                      onBackPressed: () async {
                        final shouldPop = await _onBackPressed();
                        if (shouldPop && context.mounted) {
                          Navigator.of(context).pop();
                        }
                      },
                      onResetPressed: _resetWorkout,
                      onToggleCameraPressed: _toggleCamera,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
