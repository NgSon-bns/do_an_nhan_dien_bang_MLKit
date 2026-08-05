import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:camera/camera.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show Supabase, FileOptions;

import 'package:demo/core/theme/app_theme.dart';

import 'package:demo/domain/exercise.dart';
import 'package:demo/domain/workout_session.dart';
import 'package:demo/data/services/pose_analysis/base_pose_evaluator.dart';
import 'package:demo/data/services/pose_analysis/evaluator_factory.dart';
import 'package:demo/data/services/pose_analysis/alignment_helper.dart';
import 'package:demo/data/services/pose_detector_service.dart';
import 'package:demo/data/services/database_service.dart';
import 'package:demo/data/services/workout_draft_service.dart';
import 'package:demo/data/services/pose_analysis/image_baking_service.dart';
import 'widgets/camera_stream_view.dart';
import 'widgets/workout_hud_panel.dart';
import 'widgets/pose_skeleton_painter.dart';

class WorkoutScreen extends StatefulWidget {
  final ExerciseDetail exercise;
  final int targetCount;
  final bool noSplit;
  final String? sourceTag;
  final List<CameraDescription> cameras;
  final int initialCompletedCount;

  const WorkoutScreen({
    super.key,
    required this.exercise,
    required this.targetCount,
    required this.noSplit,
    this.sourceTag,
    required this.cameras,
    this.initialCompletedCount = 0,
  });

  @override
  State<WorkoutScreen> createState() => _WorkoutScreenState();
}

class _WorkoutScreenState extends State<WorkoutScreen> {
  late CameraController _cameraController;
  late PoseDetectorService _poseDetectorService;
  final WorkoutDraftService _workoutDraftService = WorkoutDraftService();

  int _currentCameraIndex = 0;
  bool _isCameraInitialized = false;
  bool _isProcessing = false;
  int _lastFrameTimeMs = 0;
  bool _isPoseDetected = false;
  bool _isFullBodyVisible = false;
  bool _isWorkoutComplete = false;
  bool _hasShownCompletionDialog = false;
  // Đối tượng lưu trữ trạng thái buổi tập
  final WorkoutSession _session = WorkoutSession();
  late final List<int> _setPlan;
  int _currentSetIndex = 0;
  int _currentSetCount = 0;
  Timer? _workoutTimer;
  Pose? _lastValidPose; // Lưu pose cuối cùng hợp lệ
  int _lostFrameCount = 0; // Đếm số frame không tìm thấy người
  final int _maxAllowedLostFrames = 15; // Khoảng 0.5 giây (nếu 30fps)
  // Dữ liệu khung xương
  List<Pose> _poses = [];

  late BasePoseEvaluator _evaluator;

  // Cờ hiệu kiểm soát lỗi tư thế để tránh cộng dồn lỗi liên tục theo từng khung hình (30fps)
  bool _wasPostureCorrectLastFrame = true;

  // Trạng thái căn chỉnh tư thế & góc camera trước khi tập
  bool _isWorkoutStarted = false;
  bool _isAligned = false;
  int _countdownSeconds = -1;
  Timer? _countdownTimer;
  int _consecutiveAlignedFrames = 0;
  final int _requiredAlignedFrames = 12; // Khoảng 0.4s để tránh nhiễu
  String _alignmentFeedback = 'Hãy di chuyển vào khung hình';
  Size? _imageSize;

  // Lưu trữ ảnh tập sai và trạng thái chụp hình
  final List<File> _capturedErrorImages = [];
  bool _isCapturingError = false;

  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
    ]);
    _poseDetectorService = PoseDetectorService();
    _poseDetectorService.initialize();
    _evaluator = EvaluatorFactory.create(widget.exercise.type);
    _setPlan = widget.noSplit
        ? [widget.targetCount]
        : ExerciseDetail.computeSetPlan(widget.targetCount);

    if (widget.exercise.isDurationBased) {
      _session.activeHoldSeconds = widget.initialCompletedCount;
    } else {
      _session.counter = widget.initialCompletedCount;
    }

    int remaining = widget.initialCompletedCount;
    _currentSetIndex = 0;
    _currentSetCount = 0;
    for (int i = 0; i < _setPlan.length; i++) {
      if (remaining >= _setPlan[i]) {
        remaining -= _setPlan[i];
        _currentSetIndex = i + 1;
      } else {
        _currentSetIndex = i;
        _currentSetCount = remaining;
        remaining = 0;
        break;
      }
    }
    if (_currentSetIndex >= _setPlan.length) {
      _currentSetIndex = _setPlan.length - 1;
      _currentSetCount = _setPlan.isEmpty ? 0 : _setPlan.last;
    }

    _session.feedbackMessage = _alignmentFeedback;

    // Thường ưu tiên camera trước (Selfie) cho tập luyện nếu có
    _findSelfieCamera();
    _initializeCamera();
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
    if (!mounted) return;

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

      setState(() {
        _isCameraInitialized = true;
      });

      await _startCameraStream();
    } catch (e) {
      debugPrint('Lỗi khởi tạo camera: $e');
    }
  }

  Future<void> _startCameraStream() async {
    if (!mounted || !_cameraController.value.isInitialized) return;
    if (_cameraController.value.isStreamingImages) return;

    _lastFrameTimeMs = 0;
    await _cameraController.startImageStream((cameraImage) {
      final now = DateTime.now().millisecondsSinceEpoch;
      if (!_isProcessing && mounted && (now - _lastFrameTimeMs >= 120)) {
        _isProcessing = true;
        _lastFrameTimeMs = now;
        _processImage(cameraImage);
      }
    });
  }

  Future<void> _stopCameraStream() async {
    if (!_cameraController.value.isInitialized ||
        !_cameraController.value.isStreamingImages) {
      return;
    }

    await _cameraController.stopImageStream();
  }

  Future<void> _pauseCameraForDialog() async {
    await _stopCameraStream();
  }

  Future<void> _resumeCameraAfterDialog() async {
    await _startCameraStream();
  }

  /// Bộ đếm thời gian tự động mỗi giây
  void _startTimer() {
    _workoutTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      setState(() {
        _session.elapsedSeconds++;

        // Dành riêng cho Plank: Chỉ tích lũy giây tập khi đúng tư thế và thấy toàn thân
        if (widget.exercise.type == ExerciseType.plank) {
          if (_isPoseDetected &&
              _session.isPostureCorrect &&
              _isFullBodyVisible) {
            _session.activeHoldSeconds++;
            if (_session.activeHoldSeconds >= widget.targetCount) {
              _isWorkoutComplete = true;
              _session.feedbackMessage =
                  'Hoàn thành bài tập! Chúc mừng bạn đã hoàn tất.';
              _session.announcementMessage =
                  'Bạn đã hoàn thành bài tập. Nghỉ ngơi và tận hưởng thành quả!';
              if (mounted && !_hasShownCompletionDialog) {
                _hasShownCompletionDialog = true;
                _workoutTimer?.cancel();
                _showCompletionDialog();
              }
            }
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

    if (_cameraController.value.isInitialized) {
      if (_cameraController.value.isStreamingImages) {
        await _cameraController.stopImageStream();
      }
      await _cameraController.dispose();
    }

    _currentCameraIndex = (_currentCameraIndex + 1) % widget.cameras.length;
    await _initializeCamera();
  }

  /// Reset bộ đếm lần tập và thời gian
  void _resetWorkout() {
    _evaluator.reset();
    _cancelCountdown();
    setState(() {
      _session.reset();
      _currentSetIndex = 0;
      _currentSetCount = 0;
      _poses.clear();
      _isPoseDetected = false;
      _wasPostureCorrectLastFrame = true;
      _isWorkoutStarted = false;
      _isAligned = false;
      _consecutiveAlignedFrames = 0;
      _session.feedbackMessage = _alignmentFeedback;
    });
  }

  void _startCountdown() {
    if (_countdownTimer != null && _countdownTimer!.isActive) return;

    setState(() {
      _countdownSeconds = 3;
      _session.announcementMessage = 'Chuẩn bị';
    });

    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        _countdownSeconds--;
        if (_countdownSeconds > 0) {
          _session.announcementMessage = '$_countdownSeconds';
        } else if (_countdownSeconds == 0) {
          _session.announcementMessage = 'Bắt đầu!';
          _isWorkoutStarted = true;
          _startTimer();
          timer.cancel();
          _countdownSeconds = -1;
        }
      });
    });
  }

  void _cancelCountdown() {
    if (_countdownTimer != null && _countdownTimer!.isActive) {
      _countdownTimer!.cancel();
      _session.announcementMessage = 'Đã hủy';
      setState(() {
        _countdownSeconds = -1;
      });
    }
  }

  void _handleNoPersonDetected() {
    _lostFrameCount++;
    if (_isWorkoutStarted &&
        _lostFrameCount < _maxAllowedLostFrames &&
        _lastValidPose != null) {
      // Dùng pose cũ để phân tích tiếp, giả định người đang thực hiện động tác
      _analyzePose(_lastValidPose!);
    } else {
      // Mất dấu quá lâu hoặc chưa tập -> Reset mọi thứ
      if (_isWorkoutStarted) {
        _evaluator.reset();
      } else {
        _consecutiveAlignedFrames = 0;
        _cancelCountdown();
      }
      if (mounted) {
        setState(() {
          _isPoseDetected = false;
          _isFullBodyVisible = false;
          _isAligned = false;
          _session.isPostureCorrect = true;
          _session.feedbackMessage = 'Hãy quay trở lại khung hình!';
        });
      }
    }
  }

  /// Phân tích hình ảnh camera bằng AI và chạy thuật toán nhận diện
  Future<void> _processImage(CameraImage image) async {
    if (_session.isResting) {
      if (mounted) {
        setState(() {
          _poses.clear();
          _isPoseDetected = false;
          _isFullBodyVisible = false;
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

    // Lưu kích thước hình ảnh để CustomPainter sử dụng
    if (poses.isNotEmpty && _imageSize == null) {
      if (mounted) {
        setState(() {
          _imageSize = Size(image.width.toDouble(), image.height.toDouble());
        });
      }
    }

    final rotation =
        InputImageRotationValue.fromRawValue(
          _cameraController.description.sensorOrientation,
        ) ??
        InputImageRotation.rotation0deg;

    if (poses.isNotEmpty) {
      final pose = poses.first;

      // Tính độ tin cậy trung bình của các khớp để loại bỏ người ảo (phantom pose)
      double totalLikelihood = 0.0;
      int landmarkCount = 0;
      for (final landmark in pose.landmarks.values) {
        totalLikelihood += landmark.likelihood;
        landmarkCount++;
      }
      double avgLikelihood = landmarkCount > 0
          ? totalLikelihood / landmarkCount
          : 0.0;

      if (avgLikelihood < 0.45) {
        // Độ tin cậy quá thấp -> Coi như không tìm thấy người thực sự
        _handleNoPersonDetected();
      } else {
        _lostFrameCount = 0;
        _lastValidPose = pose;
        _isPoseDetected = true;

        if (!_isWorkoutStarted) {
          // Giai đoạn căn chỉnh tư thế
          final alignmentResult = AlignmentHelper.checkAlignment(
            pose: pose,
            exerciseType: widget.exercise.type,
            screenSize: MediaQuery.of(context).size,
            imageSize: Size(image.width.toDouble(), image.height.toDouble()),
            rotation: rotation,
            isFrontCamera:
                _cameraController.description.lensDirection ==
                CameraLensDirection.front,
          );

          if (mounted) {
            setState(() {
              _isFullBodyVisible = alignmentResult.isBodyInFrame;
              _isAligned = alignmentResult.isAligned;
              _alignmentFeedback = alignmentResult.feedbackMessage;
              _session.feedbackMessage = alignmentResult.feedbackMessage;
            });
          }

          if (alignmentResult.isAligned) {
            _consecutiveAlignedFrames++;
            if (_consecutiveAlignedFrames >= _requiredAlignedFrames &&
                _countdownSeconds == -1) {
              _startCountdown();
            }
          } else {
            _consecutiveAlignedFrames = 0;
            _cancelCountdown();
          }
        } else {
          // Giai đoạn tập luyện bình thường
          // Kiểm tra xem camera có nhìn rõ toàn bộ cơ thể để phân tích không
          if (_checkFullBodyVisibility(pose, widget.exercise.type)) {
            _isFullBodyVisible = true;
            _analyzePose(pose);
          } else {
            _isFullBodyVisible = false;
            if (mounted) {
              setState(() {
                _session.isPostureCorrect = true;
                if (widget.exercise.type == ExerciseType.push_up ||
                    widget.exercise.type == ExerciseType.plank) {
                  _session.feedbackMessage =
                      'Hãy điều chỉnh tư thế để camera thấy rõ từ đầu đến chân!';
                } else {
                  _session.feedbackMessage =
                      'Hãy đứng lùi lại để camera thấy rõ toàn thân!';
                }
              });
            }
          }
        }
      }
    } else {
      _handleNoPersonDetected();
    }

    if (mounted) {
      setState(() {
        _poses = poses;
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
      _captureIncorrectPose(pose, result.feedbackMessage ?? 'Sai tư thế');
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
          _isWorkoutComplete = true;
          _session.feedbackMessage =
              'Hoàn thành bài tập! Chúc mừng bạn đã hoàn tất.';
          _session.announcementMessage =
              'Bạn đã hoàn thành bài tập. Nghỉ ngơi và tận hưởng thành quả!';
          if (mounted && !_hasShownCompletionDialog) {
            _hasShownCompletionDialog = true;
            _workoutTimer?.cancel();
            _showCompletionDialog();
          }
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

  Future<void> _captureIncorrectPose(Pose pose, String feedbackMessage) async {
    if (_isCapturingError || _capturedErrorImages.length >= 3) return;
    _isCapturingError = true;

    try {
      // 1. Chụp ảnh thứ nhất ngay lập tức (Bắt đầu sai)
      await _executeSingleCapture(pose, '$feedbackMessage (Bắt đầu sai)');

      // 2. Chụp ảnh thứ hai sau 600ms nếu vẫn đang ở tư thế sai và chưa đủ 3 ảnh
      await Future.delayed(const Duration(milliseconds: 600));
      if (mounted && !_session.isPostureCorrect && _capturedErrorImages.length < 3) {
        final currentPose = _poses.isNotEmpty ? _poses.first : pose;
        await _executeSingleCapture(currentPose, '$feedbackMessage (Giữa nhịp)');
      }

      // 3. Chụp ảnh thứ ba sau 600ms nữa nếu vẫn đang ở tư thế sai và chưa đủ 3 ảnh
      await Future.delayed(const Duration(milliseconds: 600));
      if (mounted && !_session.isPostureCorrect && _capturedErrorImages.length < 3) {
        final currentPose = _poses.isNotEmpty ? _poses.first : pose;
        await _executeSingleCapture(currentPose, '$feedbackMessage (Cuối nhịp)');
      }
    } catch (e) {
      debugPrint('Lỗi chuỗi chụp ảnh sai tư thế: $e');
    } finally {
      _isCapturingError = false;
    }
  }

  Future<void> _executeSingleCapture(Pose pose, String label) async {
    if (!_cameraController.value.isInitialized) return;
    final XFile photo = await _cameraController.takePicture();
    final File originalFile = File(photo.path);

    final Map<String, Offset> landmarksMap = {};
    final List<PoseLandmarkType> interestJoints = [
      PoseLandmarkType.leftShoulder,
      PoseLandmarkType.rightShoulder,
      PoseLandmarkType.leftElbow,
      PoseLandmarkType.rightElbow,
      PoseLandmarkType.leftWrist,
      PoseLandmarkType.rightWrist,
      PoseLandmarkType.leftHip,
      PoseLandmarkType.rightHip,
      PoseLandmarkType.leftKnee,
      PoseLandmarkType.rightKnee,
      PoseLandmarkType.leftAnkle,
      PoseLandmarkType.rightAnkle,
    ];

    for (var type in interestJoints) {
      final lm = pose.landmarks[type];
      if (lm != null) {
        String name = type.name;
        if (name.contains('left')) {
          name = name.replaceAll('left', '').toLowerCase();
        } else if (name.contains('right')) {
          name = name.replaceAll('right', '').toLowerCase();
        }
        landmarksMap[name] = Offset(lm.x, lm.y);
      }
    }

    final double sWidth = _imageSize?.width ?? 640.0;
    final double sHeight = _imageSize?.height ?? 480.0;

    final ImageBakingService bakingService = ImageBakingService();
    final File bakedFile = await bakingService.bakeSkeleton(
      originalImageFile: originalFile,
      landmarks: landmarksMap,
      streamWidth: sWidth,
      streamHeight: sHeight,
      exerciseId: widget.exercise.type.name,
      errorMessage: label,
      isPostureCorrect: false,
      sensorOrientation: _cameraController.description.sensorOrientation,
      isFrontCamera: _cameraController.description.lensDirection == CameraLensDirection.front,
    );

    _capturedErrorImages.add(bakedFile);
    debugPrint('Đã chụp nhịp sai tư thế: $label -> ${bakedFile.path}');
  }

  Future<List<String>> _uploadErrorImages() async {
    final List<String> urls = [];
    if (_capturedErrorImages.isEmpty) return urls;

    try {
      final supabase = Supabase.instance.client;
      final userId = supabase.auth.currentUser?.id;
      if (userId == null) return urls;

      final workoutId = DateTime.now().millisecondsSinceEpoch.toString();

      for (int i = 0; i < _capturedErrorImages.length; i++) {
        final File file = _capturedErrorImages[i];
        final String storagePath = '$userId/$workoutId/loi_$i.png';

        // Tải ảnh lên bucket 'anh_tap_sai'
        await supabase.storage.from('anh_tap_sai').upload(
          storagePath,
          file,
          fileOptions: const FileOptions(cacheControl: '3600', upsert: true),
        );

        // Lấy URL công khai
        final String publicUrl = supabase.storage.from('anh_tap_sai').getPublicUrl(storagePath);
        urls.add(publicUrl);
      }
    } catch (e) {
      debugPrint('Lỗi tải ảnh lỗi lên Supabase: $e');
    }
    return urls;
  }

  /// Thuật toán kiểm tra toàn thân người hoàn chỉnh trước khi nhận diện (Độ tin cậy >= 0.70)
  bool _checkFullBodyVisibility(Pose pose, ExerciseType type) {
    print('Checking full body visibility for ${type.name}...');
    if (type == ExerciseType.burpee) {
      print("ok");
      return true;
    }
    const double standardConfidence = 0.75;
    const double strictConfidence = 0.82;

    bool isJointVisible(PoseLandmark? landmark, double threshold) {
      return landmark != null && landmark.likelihood >= threshold;
    }

    // 1. Đối với Squat, Jumping Jack và Walking Lunge (bắt buộc trực diện, đủ 2 bên trái & phải)
    if (type == ExerciseType.squat ||
        type == ExerciseType.jumping_jack ||
        type == ExerciseType.walking_lunge) {
      final standardJoints = [
        PoseLandmarkType.leftShoulder,
        PoseLandmarkType.rightShoulder,
        PoseLandmarkType.leftHip,
        PoseLandmarkType.rightHip,
        if (type == ExerciseType.jumping_jack) ...[
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
      if (type == ExerciseType.push_up || type == ExerciseType.plank) ...[
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
      if (type == ExerciseType.push_up || type == ExerciseType.plank) ...[
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
    // Khóa lại màn hình dọc mặc định cho toàn bộ các màn hình khác của ứng dụng khi thoát
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    _countdownTimer?.cancel();
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

  Future<void> _showCompletionDialog() async {
    await _pauseCameraForDialog();

    final isOffline = !_isSupabaseInitialized;
    final isDuration = widget.exercise.isDurationBased;
    final scoreValue = isDuration
        ? _session.activeHoldSeconds
        : _session.counter;
    final scoreUnit = isDuration ? 'giây' : 'lần';

    final dialogContext = context;
    bool? result = await showDialog<bool>(
      context: dialogContext,
      barrierDismissible: false,
      builder: (dialogContext) {
        final isLandscape =
            MediaQuery.of(dialogContext).orientation == Orientation.landscape;
        final spacing = isLandscape ? 8.0 : 16.0;

        return AlertDialog(
          backgroundColor: AppTheme.cardBackground,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          contentPadding: EdgeInsets.symmetric(
            horizontal: 24,
            vertical: isLandscape ? 8 : 20,
          ),
          title: Padding(
            padding: EdgeInsets.only(top: isLandscape ? 4 : 8),
            child: Center(
              child: Text(
                'Kết quả tập luyện'.toUpperCase(),
                style: TextStyle(
                  color: AppTheme.neonGreen,
                  fontWeight: FontWeight.bold,
                  fontSize: isLandscape ? 14 : 16,
                  letterSpacing: 1.0,
                ),
              ),
            ),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Divider(color: Colors.white12),
                SizedBox(height: spacing),
                Text(
                  '$scoreValue $scoreUnit',
                  style: TextStyle(
                    fontSize: isLandscape ? 28 : 36,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                  ),
                ),
                SizedBox(height: spacing),
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
                SizedBox(height: spacing),
                const Divider(color: Colors.white12),
                SizedBox(height: isLandscape ? 4 : 8),
                Text(
                  isOffline
                      ? 'Ứng dụng chạy ở chế độ Offline. Kết quả sẽ không được lưu lên Cloud.'
                      : 'Kết quả sẽ được đồng bộ trực tuyến lên tài khoản của bạn.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          actionsPadding: EdgeInsets.symmetric(
            horizontal: 16,
            vertical: isLandscape ? 4 : 12,
          ),
          actionsAlignment: MainAxisAlignment.spaceAround,
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text(
                'Thoát',
                style: TextStyle(
                  color: AppTheme.errorRed,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
           ElevatedButton(
              onPressed: () async {
                // 1. Chạy hàm xóa nháp (đảm bảo hàm này có async/await)
                await _workoutDraftService.clearTodayDraftWorkout();
              
                // 3. Đóng dialog và trả về kết quả
                if (context.mounted) {
                  Navigator.pop(dialogContext, true);
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.neonGreen,
                padding: EdgeInsets.symmetric(
                  horizontal: isLandscape ? 12 : 20,
                  vertical: isLandscape ? 8 : 12,
                ),
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
            )

          ],
        );
      },
    );

    await _resumeCameraAfterDialog();

    if (result == null) {
      return;
    }

    if (result == true && !isOffline) {
      if (!mounted) return;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (loadingContext) => const Center(
          child: CircularProgressIndicator(color: AppTheme.neonGreen),
        ),
      );

      try {
        final List<String> imageUrls = await _uploadErrorImages();
        await DatabaseService().saveWorkoutResult(
          exerciseType: widget.exercise.type.name,
          repsCount: _session.counter,
          durationSeconds: _session.elapsedSeconds,
          caloriesBurned: _session.caloriesBurned,
          incorrectPostures: _session.incorrectPostureCount,
          sourceTag: widget.sourceTag,
          danhSachAnhSai: imageUrls.isNotEmpty ? imageUrls : null,
        );
      } catch (e) {
        debugPrint('Lỗi lưu kết quả: $e');
      }

      if (!mounted) return;
      Navigator.pop(context); // Đóng loading spinner
    }

    if (mounted) {
      await _checkAndHandleTooHeavyWorkout();
      if (mounted) {
        Navigator.pop(context, 'complete');
      }
    }
  }

  Future<dynamic> _onBackPressed() async {
    // Tạm dừng timer khi hiện dialog
    _workoutTimer?.cancel();
    await _pauseCameraForDialog();

    final isOffline = !_isSupabaseInitialized;
    final isDuration = widget.exercise.isDurationBased;
    final scoreValue = isDuration
        ? _session.activeHoldSeconds
        : _session.counter;
    final scoreUnit = isDuration ? 'giây' : 'lần';

    final dialogContext = context;
    final result = await showDialog<dynamic>(
      context: dialogContext,
      barrierDismissible: false,
      builder: (builderContext) {
        final isLandscape =
            MediaQuery.of(builderContext).orientation == Orientation.landscape;
        final spacing = isLandscape ? 8.0 : 16.0;

        return AlertDialog(
          backgroundColor: AppTheme.cardBackground,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          contentPadding: EdgeInsets.symmetric(
            horizontal: 24,
            vertical: isLandscape ? 8 : 20,
          ),
          title: Padding(
            padding: EdgeInsets.only(top: isLandscape ? 4 : 8),
            child: Center(
              child: Text(
                'Kết quả tập luyện'.toUpperCase(),
                style: TextStyle(
                  color: AppTheme.neonGreen,
                  fontWeight: FontWeight.bold,
                  fontSize: isLandscape ? 14 : 16,
                  letterSpacing: 1.0,
                ),
              ),
            ),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Divider(color: Colors.white12),
                SizedBox(height: spacing),

                Text(
                  '$scoreValue $scoreUnit',
                  style: TextStyle(
                    fontSize: isLandscape ? 28 : 36,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                  ),
                ),
                SizedBox(height: spacing),

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
                SizedBox(height: spacing),
                const Divider(color: Colors.white12),
                SizedBox(height: isLandscape ? 4 : 8),
                Text(
                  isOffline
                      ? 'Ứng dụng chạy ở chế độ Offline. Kết quả sẽ không được lưu lên Cloud.'
                      : 'Kết quả sẽ được đồng bộ trực tuyến lên tài khoản của bạn.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          actionsPadding: EdgeInsets.symmetric(
            horizontal: 16,
            vertical: isLandscape ? 4 : 12,
          ),
          actionsAlignment: MainAxisAlignment.spaceAround,
          actions: [
            if (!_isWorkoutComplete)
              TextButton(
                onPressed: () => Navigator.pop(builderContext, 'exit'),
                child: const Text(
                  'Thoát',
                  style: TextStyle(
                    color: AppTheme.errorRed,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),

            // Nút "Tập tiếp" chỉ hiện nếu CHƯA hoàn thành
            if (!_isWorkoutComplete) ...[
              TextButton(
                onPressed: () async {
                  await _workoutDraftService.saveDraftWorkout(
                    exerciseType: widget.exercise.type.name,
                    exerciseName: widget.exercise.name,
                    targetCount: widget.targetCount,
                    noSplit: widget.noSplit,
                    completedCount: widget.exercise.isDurationBased
                        ? _session.activeHoldSeconds
                        : _session.counter,
                    sourceTag: widget.sourceTag,
                  );
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Đã lưu tạm bài tập hôm nay.'),
                      duration: Duration(seconds: 2),
                    ),
                  );
                  Navigator.pop(builderContext, 'draft');
                },
                child: const Text(
                  'Lưu tạm',
                  style: TextStyle(color: AppTheme.neonGreen),
                ),
              ),
              TextButton(
                onPressed: () {
                  _startTimer();
                  Navigator.pop(builderContext, 'resume');
                },
                child: const Text(
                  'Tập tiếp',
                  style: TextStyle(color: Colors.grey),
                ),
              ),
            ],

            // Nút "Lưu & Thoát" chỉ hiện nếu ĐÃ hoàn thành (hoặc tùy ý logic của bạn)
            if (_isWorkoutComplete)
              ElevatedButton(
                onPressed: () => Navigator.pop(builderContext, 'complete'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.neonGreen,
                  padding: EdgeInsets.symmetric(
                    horizontal: isLandscape ? 12 : 20,
                    vertical: isLandscape ? 8 : 12,
                  ),
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
        );
      },
    );

    await _resumeCameraAfterDialog();

    if (result == null || result == 'resume') {
      return false; // Ở lại màn hình
    }

    if (result == 'complete' && !isOffline) {
      if (!mounted) return 'complete';
      // Hiện loading spinner
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(
          child: CircularProgressIndicator(color: AppTheme.neonGreen),
        ),
      );

      try {
        final List<String> imageUrls = await _uploadErrorImages();
        await DatabaseService().saveWorkoutResult(
          exerciseType: widget.exercise.type.name,
          repsCount: _session.counter,
          durationSeconds: _session.elapsedSeconds,
          caloriesBurned: _session.caloriesBurned,
          incorrectPostures: _session.incorrectPostureCount,
          sourceTag: widget.sourceTag,
          danhSachAnhSai: imageUrls.isNotEmpty ? imageUrls : null,
        );
      } catch (e) {
        debugPrint('Lỗi lưu kết quả: $e');
      }

      if (!mounted) return 'complete';
      Navigator.pop(context); // Đóng loading spinner
    }

    return result; // Trả về 'draft', 'exit', hoặc 'complete'
  }

  void _skipRest() {
    if (_session.isResting) {
      setState(() {
        _session.isResting = false;
        _session.restSecondsLeft = 0;
        _session.announcementMessage = 'Kết thúc nghỉ. Bắt đầu set tiếp theo.';
        _session.feedbackMessage = 'Bắt đầu set tiếp theo!';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final popResult = await _onBackPressed();
        if (popResult != false && popResult != null && context.mounted) {
          if (popResult == 'complete' || popResult == 'exit') {
            await _checkAndHandleTooHeavyWorkout();
          }
          if (context.mounted) {
            Navigator.of(context).pop(popResult);
          }
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

                  // 2. Khung xương Pose Skeleton Painter (Hiển thị đè lên camera)
                  if (_poses.isNotEmpty && _imageSize != null)
                    Positioned.fill(
                      child: CustomPaint(
                        painter: PoseSkeletonPainter(
                          pose: _poses.first,
                          imageSize: _imageSize!,
                          rotation:
                              InputImageRotationValue.fromRawValue(
                                _cameraController.description.sensorOrientation,
                              ) ??
                              InputImageRotation.rotation0deg,
                          isFrontCamera:
                              _cameraController.description.lensDirection ==
                              CameraLensDirection.front,
                          isBackCorrect: _session.isPostureCorrect,
                          isLegsCorrect: true,
                          isArmsCorrect: true,
                        ),
                      ),
                    ),

                  // 3. Khung chữ nhật căn chỉnh phát sáng (glowing cutout overlay)
                  if (!_isWorkoutStarted)
                    Positioned.fill(
                      child: Builder(
                        builder: (context) {
                          final screenSize = MediaQuery.of(context).size;
                          final isHorizontal =
                              AlignmentHelper.isHorizontalLayout(
                                widget.exercise.type,
                              );
                          final double boxWidth;
                          final double boxHeight;
                          final double boxLeft;
                          final double boxTop;

                          if (isHorizontal) {
                            boxWidth = screenSize.width * 0.90;
                            boxHeight = screenSize.height * 0.45;
                            boxLeft = (screenSize.width - boxWidth) / 2;
                            boxTop = (screenSize.height - boxHeight) / 2 + 60;
                          } else {
                            boxWidth = screenSize.width * 0.65;
                            boxHeight = screenSize.height * 0.80;
                            boxLeft = (screenSize.width - boxWidth) / 2;
                            boxTop = (screenSize.height - boxHeight) / 2;
                          }

                          final rect = Rect.fromLTWH(
                            boxLeft,
                            boxTop,
                            boxWidth,
                            boxHeight,
                          );
                          return CustomPaint(
                            painter: AlignmentFramePainter(
                              rect: rect,
                              isAligned: _isAligned,
                            ),
                          );
                        },
                      ),
                    ),

                  // 5. Hiển thị đếm ngược 3s kích thước lớn ở tâm
                  if (!_isWorkoutStarted && _countdownSeconds > 0)
                    Positioned.fill(
                      child: Container(
                        color: Colors.black45,
                        child: Center(
                          child: TweenAnimationBuilder<double>(
                            key: ValueKey<int>(_countdownSeconds),
                            tween: Tween<double>(begin: 1.6, end: 1.0),
                            duration: const Duration(milliseconds: 600),
                            builder: (context, value, child) {
                              return Transform.scale(
                                scale: value,
                                child: Text(
                                  '$_countdownSeconds',
                                  style: TextStyle(
                                    fontSize: 160,
                                    fontWeight: FontWeight.w900,
                                    color: AppTheme.neonGreen,
                                    shadows: [
                                      Shadow(
                                        color: Colors.black.withValues(
                                          alpha: 0.8,
                                        ),
                                        offset: const Offset(0, 12),
                                        blurRadius: 24,
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                    ),

                  // 6. Bảng HUD hiển thị thông số và cảnh báo
                  Positioned.fill(
                    child: WorkoutHudPanel(
                      exercise: widget.exercise,
                      targetCount: widget.targetCount,
                      noSplit: widget.noSplit,
                      session: _session,
                      feedbackMessage: _session.feedbackMessage,
                      isPostureCorrect: _session.isPostureCorrect,
                      announcementMessage: _session.announcementMessage,
                      isWorkoutStarted: _isWorkoutStarted,
                      onBackPressed: () async {
                        final popResult = await _onBackPressed();
                        if (popResult != false && popResult != null && context.mounted) {
                          if (popResult == 'complete' || popResult == 'exit') {
                            await _checkAndHandleTooHeavyWorkout();
                          }
                          if (context.mounted) {
                            Navigator.of(context).pop(popResult);
                          }
                        }
                      },
                      onResetPressed: _resetWorkout,
                      onToggleCameraPressed: _toggleCamera,
                      onSkipRestPressed: _skipRest,
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Future<void> _checkAndHandleTooHeavyWorkout() async {
    // Chỉ kích hoạt nếu người dùng tập sai quá nhiều (từ 5 lần trở lên)
    if (_session.incorrectPostureCount >= 5) {
      final dialogContext = context;
      bool? changeGoal = await showDialog<bool>(
        context: dialogContext,
        barrierDismissible: false,
        builder: (dialogCtx) => AlertDialog(
          backgroundColor: AppTheme.cardBackground,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Row(
            children: const [
              Icon(Icons.warning_amber_rounded, color: AppTheme.errorRed),
              SizedBox(width: 8),
              Text(
                'Cảnh Báo Độ Khó',
                style: TextStyle(
                  color: AppTheme.errorRed,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ],
          ),
          content: Text(
            'Bài tập ${widget.exercise.name} có vẻ hơi quá sức với bạn (bạn đã tập sai ${_session.incorrectPostureCount} lần).\n\nBạn có muốn hệ thống tự động đổi bài tập này sang bài tập khác nhẹ hơn để tránh chấn thương không?',
            style: const TextStyle(color: Colors.white, fontSize: 13),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx, false),
              child: const Text(
                'Không cần',
                style: TextStyle(color: Colors.grey),
              ),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(dialogCtx, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.neonGreen,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: const Text(
                'Đồng ý đổi',
                style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      );

      if (changeGoal == true) {
        try {
          final userId = _isSupabaseInitialized
              ? Supabase.instance.client.auth.currentUser?.id
              : null;
          final String prefsKey = 'heavy_exercises_${userId ?? 'guest'}';

          final prefs = await SharedPreferences.getInstance();
          final List<String> heavyList = prefs.getStringList(prefsKey) ?? [];
          final String exTypeName = widget.exercise.type.name;
          if (!heavyList.contains(exTypeName)) {
            heavyList.add(exTypeName);
            // 1. Lưu cache cục bộ (gắn theo user hiện tại) để hoạt động cả khi offline
            await prefs.setStringList(prefsKey, heavyList);

            // 2. Đồng bộ lên Database (bảng ho_so_nguoi_dung, cột bai_tap_qua_nang)
            if (userId != null) {
              try {
                await Supabase.instance.client
                    .from('ho_so_nguoi_dung')
                    .update({'bai_tap_qua_nang': heavyList})
                    .eq('ma_nguoi_dung', userId);
              } catch (dbError) {
                debugPrint('Lỗi đồng bộ bài tập quá nặng lên CSDL: $dbError');
              }
            }
          }
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Đã tự động cập nhật lịch tập phù hợp hơn cho bạn!'),
                backgroundColor: AppTheme.neonGreen,
                duration: Duration(seconds: 3),
              ),
            );
          }
        } catch (e) {
          debugPrint('Lỗi lưu bài tập quá nặng: $e');
        }
      }
    }
  }
}

class AlignmentFramePainter extends CustomPainter {
  final Rect rect;
  final bool isAligned;

  AlignmentFramePainter({required this.rect, required this.isAligned});

  @override
  void paint(Canvas canvas, Size size) {
    // 1. Vẽ lớp phủ mờ tối màu xung quanh khung chữ nhật cắt (Cutout)
    final backgroundPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.65)
      ..style = PaintingStyle.fill;

    final path = Path()..addRect(Rect.fromLTWH(0, 0, size.width, size.height));

    // Tạo cutout bằng cách trừ đi hình chữ nhật bo góc ở giữa
    final RRect rrect = RRect.fromRectAndRadius(
      rect,
      const Radius.circular(20),
    );
    final cutoutPath = Path()..addRRect(rrect);

    // Sử dụng Path.combine với Operation.difference
    final finalPath = Path.combine(PathOperation.difference, path, cutoutPath);
    canvas.drawPath(finalPath, backgroundPaint);

    // 2. Vẽ viền bo góc phát sáng của khung chữ nhật
    final borderPaint = Paint()
      ..color = isAligned ? AppTheme.neonGreen : Colors.orangeAccent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.5;

    // Hiệu ứng phát sáng neon bằng mặt nạ mờ (MaskFilter)
    final glowPaint = Paint()
      ..color = (isAligned ? AppTheme.neonGreen : Colors.orangeAccent)
          .withValues(alpha: 0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 10.0
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6.0);

    canvas.drawRRect(rrect, glowPaint);
    canvas.drawRRect(rrect, borderPaint);

    // 3. Vẽ 4 góc nhọn (Corner brackets) để tạo cảm giác công nghệ AI
    final bracketPaint = Paint()
      ..color = isAligned ? AppTheme.neonGreen : Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5.0
      ..strokeCap = StrokeCap.round;

    const double length = 25.0; // chiều dài góc vuông

    // Góc trên bên trái
    canvas.drawLine(
      Offset(rect.left, rect.top + length),
      Offset(rect.left, rect.top),
      bracketPaint,
    );
    canvas.drawLine(
      Offset(rect.left, rect.top),
      Offset(rect.left + length, rect.top),
      bracketPaint,
    );

    // Góc trên bên phải
    canvas.drawLine(
      Offset(rect.right, rect.top + length),
      Offset(rect.right, rect.top),
      bracketPaint,
    );
    canvas.drawLine(
      Offset(rect.right, rect.top),
      Offset(rect.right - length, rect.top),
      bracketPaint,
    );

    // Góc dưới bên trái
    canvas.drawLine(
      Offset(rect.left, rect.bottom - length),
      Offset(rect.left, rect.bottom),
      bracketPaint,
    );
    canvas.drawLine(
      Offset(rect.left, rect.bottom),
      Offset(rect.left + length, rect.bottom),
      bracketPaint,
    );

    // Góc dưới bên phải
    canvas.drawLine(
      Offset(rect.right, rect.bottom - length),
      Offset(rect.right, rect.bottom),
      bracketPaint,
    );
    canvas.drawLine(
      Offset(rect.right, rect.bottom),
      Offset(rect.right - length, rect.bottom),
      bracketPaint,
    );
  }

  @override
  bool shouldRepaint(covariant AlignmentFramePainter oldDelegate) {
    return oldDelegate.rect != rect || oldDelegate.isAligned != isAligned;
  }
}