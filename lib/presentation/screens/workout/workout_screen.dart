import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:camera/camera.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import 'package:supabase_flutter/supabase_flutter.dart'
    show Supabase, FileOptions;

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
import 'package:shared_preferences/shared_preferences.dart';

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
  final WorkoutSession _session = WorkoutSession();

  // --- ĐẾM BẰNG GIỌNG NÓI (TEXT-TO-SPEECH) ---
  final FlutterTts _flutterTts = FlutterTts();
  bool _isSpeaking = false;
  final List<String> _speechQueue = [];
  int _speechGeneration = 0;
  int _lastAnnouncedRestSecond = -1;
  late final List<int> _setPlan;
  int _currentSetIndex = 0;
  int _currentSetCount = 0;
  Timer? _workoutTimer;
  Pose? _lastValidPose;
  int _lostFrameCount = 0;
  final int _maxAllowedLostFrames = 15;

  List<Pose> _poses = [];

  late BasePoseEvaluator _evaluator;

  bool _wasPostureCorrectLastFrame = true;

  bool _isWorkoutStarted = false;
  bool _isAligned = false;
  int _countdownSeconds = -1;
  Timer? _countdownTimer;
  int _consecutiveAlignedFrames = 0;
  final int _requiredAlignedFrames = 12;
  String _alignmentFeedback = 'Hãy di chuyển vào khung hình';
  Size? _imageSize;

  final List<File> _capturedErrorImages = [];
  bool _isCapturingError = false;
  final Set<String> _capturedErrorTypes = {};

  // --- BIẾN ĐO LƯỜNG HIỆU NĂNG & FPS ---
  int _cameraFrameCounter = 0;
  int _processedFrameCounter = 0;
  int _currentCaptureFps = 0;
  int _currentProcessedFps = 0;
  Timer? _performanceTimer;
  int _lastExecutionMs = 0; // Lưu thời gian xử lý frame gần nhất (ms)

  // --- BỘ LỌC NHIỄU TỌA ĐỘ (MOVING AVERAGE / LOW-PASS FILTER) ---
  final Map<PoseLandmarkType, List<Offset>> _landmarkHistory = {};
  final int _filterWindowSize = 3; // Số frame dùng để lấy trung bình

  Pose _applyLowPassFilter(Pose currentPose) {
    Map<PoseLandmarkType, PoseLandmark> filteredLandmarks = {};

    currentPose.landmarks.forEach((type, landmark) {
      _landmarkHistory.putIfAbsent(type, () => []);

      _landmarkHistory[type]!.add(Offset(landmark.x, landmark.y));

      if (_landmarkHistory[type]!.length > _filterWindowSize) {
        _landmarkHistory[type]!.removeAt(0);
      }

      double avgX = 0;
      double avgY = 0;
      int count = _landmarkHistory[type]!.length;
      for (var point in _landmarkHistory[type]!) {
        avgX += point.dx;
        avgY += point.dy;
      }
      avgX /= count;
      avgY /= count;

      filteredLandmarks[type] = PoseLandmark(
        type: landmark.type,
        x: avgX,
        y: avgY,
        z: landmark.z,
        likelihood: landmark.likelihood,
      );
    });

    return Pose(landmarks: filteredLandmarks);
  }
  // -------------------------------------------------------------

  // --- KHỞI TẠO & PHÁT GIỌNG NÓI ĐẾM SỐ ---
  Future<void> _initTts() async {
    try {
      await _flutterTts.setLanguage('vi-VN');
      await _flutterTts.setSpeechRate(0.55);
      await _flutterTts.setPitch(1.0);
      await _flutterTts.setVolume(1.0);
      // Chờ 1 câu đọc xong hẳn rồi mới coi là "rảnh" để đọc câu tiếp theo
      // trong hàng đợi -> không còn tình trạng số bị cắt ngang hay bỏ sót.
      await _flutterTts.awaitSpeakCompletion(true);
      _flutterTts.setErrorHandler((_) {
        _isSpeaking = false;
      });
    } catch (e) {
      // Không để lỗi khởi tạo TTS (thiếu plugin, thiết bị không hỗ trợ...)
      // làm ảnh hưởng đến các chức năng khác của màn hình tập luyện.
      debugPrint('Lỗi khởi tạo TTS (bỏ qua, không ảnh hưởng đếm rep/plank): $e');
    }
  }

  /// Thêm một câu/cụm từ vào hàng đợi đọc (dùng cho thông báo như
  /// "Nghỉ 30 giây", "Bắt đầu!"...). Đọc TUẦN TỰ, không chồng tiếng.
  void _enqueueText(String text) {
    try {
      if (_speechQueue.isNotEmpty && _speechQueue.last == text) return;
      _speechQueue.add(text);
      _speakNextInQueue();
    } catch (e) {
      debugPrint('Lỗi enqueue TTS (bỏ qua): $e');
    }
  }

  /// Thêm một con số vào hàng đợi đọc. Các số được đọc TUẦN TỰ, không
  /// chồng lên nhau và không bị cắt ngang, nên không bị "nhảy số".
  void _enqueueSpeak(int count) => _enqueueText('$count');

  /// Đọc NGAY LẬP TỨC, ưu tiên hơn mọi thứ đang chờ trong hàng đợi (đếm
  /// rep, đếm giây plank, thông báo nghỉ...). Dùng cho cảnh báo sai tư thế
  /// -> người tập cần nghe ngay, không được để chờ đọc hết số đang đếm dở.
  void _speakPriority(String text) {
    try {
      // Tăng "thế hệ" để vòng lặp đọc hiện tại (nếu đang chạy) tự dừng lại
      // ở lần kiểm tra kế tiếp, thay vì tiếp tục đọc nốt hàng đợi cũ.
      _speechGeneration++;
      _speechQueue
        ..clear()
        ..add(text);
      _flutterTts.stop(); // Cắt ngang câu đang đọc dở ngay lập tức
      _isSpeaking = false;
      _speakNextInQueue();
    } catch (e) {
      debugPrint('Lỗi ưu tiên TTS (bỏ qua): $e');
    }
  }

  /// Xử lý hàng đợi bằng MỘT vòng lặp duy nhất (không dựa vào completion
  /// handler để gọi đệ quy), tránh tình trạng chạy chồng hai tiến trình
  /// đọc cùng lúc. Kiểm tra "thế hệ" (generation) ở mỗi bước để tự dừng
  /// ngay khi có yêu cầu đọc ưu tiên chen ngang.
  Future<void> _speakNextInQueue() async {
    if (_isSpeaking) return;
    _isSpeaking = true;
    final int myGeneration = _speechGeneration;
    try {
      while (_speechQueue.isNotEmpty && myGeneration == _speechGeneration) {
        final String next = _speechQueue.removeAt(0);
        await _flutterTts.speak(next);
      }
    } catch (e) {
      debugPrint('Lỗi phát TTS (bỏ qua, không ảnh hưởng đếm rep/plank): $e');
    } finally {
      // Chỉ vòng lặp thuộc "thế hệ" hiện tại mới được phép reset cờ, để
      // tránh vòng lặp cũ (đã bị ngắt) ghi đè trạng thái của vòng lặp mới.
      if (myGeneration == _speechGeneration) {
        _isSpeaking = false;
      }
    }
  }

  void _clearSpeechQueue() {
    _speechGeneration++;
    _speechQueue.clear();
    try {
      _flutterTts.stop();
    } catch (e) {
      debugPrint('Lỗi dừng TTS (bỏ qua): $e');
    }
    _isSpeaking = false;
  }
  // -------------------------------------------------------------

  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    _poseDetectorService = PoseDetectorService();
    _poseDetectorService.initialize();
    _initTts();
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

    _findSelfieCamera();
    _initializeCamera();

    // Khởi động bộ đếm FPS và hiệu năng mỗi giây
    _performanceTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      setState(() {
        _currentCaptureFps = _cameraFrameCounter;
        _currentProcessedFps = _processedFrameCounter;
        _cameraFrameCounter = 0;
        _processedFrameCounter = 0;
      });
      print(
        'PERFORMANCE -> Camera FPS: $_currentCaptureFps | Processed FPS: $_currentProcessedFps | Time per frame: ${_lastExecutionMs}ms',
      );
    });
  }

  void _findSelfieCamera() {
    for (int i = 0; i < widget.cameras.length; i++) {
      if (widget.cameras[i].lensDirection == CameraLensDirection.front) {
        _currentCameraIndex = i;
        return;
      }
    }
    _currentCameraIndex = 0;
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
      await _cameraController.setFocusMode(FocusMode.locked);
      await _cameraController.setExposureMode(ExposureMode.locked);
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
      _cameraFrameCounter++; // Đếm tổng số frame camera trả về

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

  void _startTimer() {
    _workoutTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      setState(() {
        _session.elapsedSeconds++;

        if (widget.exercise.type == ExerciseType.plank) {
          final bool isHoldingCorrectly =
              _isPoseDetected &&
              _session.isPostureCorrect &&
              _isFullBodyVisible;

          if (isHoldingCorrectly) {
            // Tư thế đúng -> đếm +1 mỗi lần tick (KHÔNG tính theo đồng hồ
            // thực DateTime.now()), để số hiển thị luôn tăng đúng từng đơn
            // vị, không bị nhảy cóc dù frame xử lý pose có bị trễ/giật.
            _session.activeHoldSeconds++;

            // Đọc to số giây mới. Vì luôn +1 mỗi lần nên giọng nói theo
            // kịp số hiển thị, không bị nhảy số hay đọc dồn cụm số.
            _enqueueSpeak(_session.activeHoldSeconds);

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
          // Tư thế sai -> không làm gì cả, giữ nguyên số giây đã đếm được
          // (dừng đếm) cho đến khi tư thế đúng trở lại.
        }

        if (_session.isResting) {
          _session.restSecondsLeft = (_session.restSecondsLeft - 1).clamp(
            0,
            30,
          );
          _session.feedbackMessage =
              'Đang nghỉ ${_session.restSecondsLeft}s. Chuẩn bị set tiếp theo.';

          // Đếm ngược bằng giọng nói trong 5 giây cuối của thời gian nghỉ.
          if (_session.restSecondsLeft > 0 &&
              _session.restSecondsLeft <= 5 &&
              _session.restSecondsLeft != _lastAnnouncedRestSecond) {
            _lastAnnouncedRestSecond = _session.restSecondsLeft;
            _enqueueSpeak(_session.restSecondsLeft);
          }

          if (_session.restSecondsLeft == 0) {
            _session.isResting = false;
            _session.announcementMessage =
                'Kết thúc nghỉ. Bắt đầu set tiếp theo.';
            _session.feedbackMessage = 'Bắt đầu set tiếp theo!';
            _lastAnnouncedRestSecond = -1;
            _enqueueText('Bắt đầu!');
          }
        }

        _session.updateCalories(
          widget.exercise.caloriesPerMin,
          isDurationBased: widget.exercise.isDurationBased,
        );
      });
    });
  }

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

  void _resetWorkout() {
    _evaluator.reset();
    _cancelCountdown();
    _clearSpeechQueue();
    _landmarkHistory.clear(); // Xóa lịch sử lọc tọa độ khi reset
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
      _lastAnnouncedRestSecond = -1;
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
      _analyzePose(_lastValidPose!);
    } else {
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

    // --- BẮT ĐẦU ĐO THỜI GIAN XỬ LÝ FRAME BẰNG STOPWATCH ---
    final stopwatch = Stopwatch()..start();

    final rawPoses = await _poseDetectorService.processCameraImage(
      image,
      _cameraController,
    );

    stopwatch.stop();
    _lastExecutionMs = stopwatch.elapsedMilliseconds;
    _processedFrameCounter++; // Đếm số frame thực tế đã xử lý AI xong

    if (!mounted) {
      _isProcessing = false;
      return;
    }

    // Áp dụng bộ lọc nhiễu tọa độ cho khung hình đầu tiên nếu có
    final poses = rawPoses.isNotEmpty
        ? [_applyLowPassFilter(rawPoses.first)]
        : <Pose>[];

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
        _handleNoPersonDetected();
      } else {
        _lostFrameCount = 0;
        _lastValidPose = pose;
        _isPoseDetected = true;

        if (!_isWorkoutStarted) {
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

  void _analyzePose(Pose pose) {
    final result = _evaluator.evaluate(pose);

    if (!result.isPostureCorrect && _wasPostureCorrectLastFrame) {
      _session.incorrectPostureCount++;
      final String errorMessage =
          result.feedbackMessage.isEmpty ? 'Sai tư thế' : result.feedbackMessage;
      _captureIncorrectPose(pose, errorMessage);
      // Ưu tiên đọc cảnh báo sai tư thế NGAY, không chờ đọc hết hàng đợi
      // đếm rep/giây plank đang dang dở.
      _speakPriority(errorMessage);
    }

    if (result.shouldCountRep) {
      _session.counter++;
      _currentSetCount++;
      _enqueueSpeak(_session.counter); // Đếm bằng giọng nói khi tập đúng
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
          _lastAnnouncedRestSecond = 30;
          _enqueueText('Nghỉ 30 giây, chuẩn bị cho set tiếp theo');
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

    setState(() {
      _session.isPostureCorrect = result.isPostureCorrect;
      if (!_session.isResting) {
        _session.feedbackMessage = result.feedbackMessage;
      }
    });

    _wasPostureCorrectLastFrame = result.isPostureCorrect;
  }

  Future<void> _captureIncorrectPose(Pose pose, String feedbackMessage) async {
    if (_isCapturingError || _capturedErrorTypes.contains(feedbackMessage))
      return;

    if (_capturedErrorTypes.length >= 3) return;

    _capturedErrorTypes.add(feedbackMessage);
    _isCapturingError = true;

    try {
      await _executeSingleCapture(pose, '$feedbackMessage (Bắt đầu sai)');

      await Future.delayed(const Duration(milliseconds: 600));
      if (mounted && !_session.isPostureCorrect) {
        final currentPose = _poses.isNotEmpty ? _poses.first : pose;
        await _executeSingleCapture(
          currentPose,
          '$feedbackMessage (Giữa nhịp)',
        );
      }

      await Future.delayed(const Duration(milliseconds: 600));
      if (mounted && !_session.isPostureCorrect) {
        final currentPose = _poses.isNotEmpty ? _poses.first : pose;
        await _executeSingleCapture(
          currentPose,
          '$feedbackMessage (Cuối nhịp)',
        );
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
      isFrontCamera:
          _cameraController.description.lensDirection ==
          CameraLensDirection.front,
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

        await supabase.storage
            .from('anh_tap_sai')
            .upload(
              storagePath,
              file,
              fileOptions: const FileOptions(
                cacheControl: '3600',
                upsert: true,
              ),
            );

        final String publicUrl = supabase.storage
            .from('anh_tap_sai')
            .getPublicUrl(storagePath);
        urls.add(publicUrl);
      }
    } catch (e) {
      debugPrint('Lỗi tải ảnh lỗi lên Supabase: $e');
    }
    return urls;
  }

  bool _checkFullBodyVisibility(Pose pose, ExerciseType type) {
    if (type == ExerciseType.burpee) {
      return true;
    }
    const double standardConfidence = 0.75;
    const double strictConfidence = 0.82;

    bool isJointVisible(PoseLandmark? landmark, double threshold) {
      return landmark != null && landmark.likelihood >= threshold;
    }

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
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    _performanceTimer?.cancel();
    _countdownTimer?.cancel();
    _workoutTimer?.cancel();
    try {
      _flutterTts.stop();
    } catch (_) {}
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
                await _workoutDraftService.clearTodayDraftWorkout();
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
            ),
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
      Navigator.pop(context);
    }

    if (mounted) {
      await _checkAndHandleTooHeavyWorkout();
      if (mounted) {
        Navigator.pop(context, 'complete');
      }
    }
  }

  Future<dynamic> _onBackPressed() async {
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
      return false;
    }

    if (result == 'complete' && !isOffline) {
      if (!mounted) return 'complete';

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
      Navigator.pop(context);
    }

    return result;
  }

  void _skipRest() {
    if (_session.isResting) {
      setState(() {
        _session.isResting = false;
        _session.restSecondsLeft = 0;
        _session.announcementMessage = 'Kết thúc nghỉ. Bắt đầu set tiếp theo.';
        _session.feedbackMessage = 'Bắt đầu set tiếp theo!';
      });
      _lastAnnouncedRestSecond = -1;
      _clearSpeechQueue();
      _enqueueText('Bắt đầu!');
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
                  CameraStreamView(controller: _cameraController),

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
                        if (popResult != false &&
                            popResult != null &&
                            context.mounted) {
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

                  // --- WIDGET HIỂN THỊ THÔNG SỐ FPS VÀ HIỆU NĂNG GÓC TRÁI ---
                  Positioned(
                    top: 50,
                    left: 20,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Camera FPS: $_currentCaptureFps',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                            ),
                          ),
                          Text(
                            'Processed FPS: $_currentProcessedFps',
                            style: const TextStyle(
                              color: Colors.greenAccent,
                              fontSize: 11,
                            ),
                          ),
                          Text(
                            'Time/Frame: ${_lastExecutionMs}ms',
                            style: const TextStyle(
                              color: Colors.amberAccent,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Future<void> _checkAndHandleTooHeavyWorkout() async {
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
                style: TextStyle(
                  color: Colors.black,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      );
      if (changeGoal == true) {
        final prefs = await SharedPreferences.getInstance();
        final list = prefs.getStringList('too_heavy_exercises') ?? [];
        final typeName = widget.exercise.type.name;
        if (!list.contains(typeName)) {
          list.add(typeName);
          await prefs.setStringList('too_heavy_exercises', list);
        }
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Đã ghi nhận! Hệ thống sẽ điều chỉnh bài tập ${widget.exercise.name} ra khỏi danh sách tập sắp tới của bạn.',
              ),
              backgroundColor: Colors.orangeAccent,
              duration: const Duration(seconds: 4),
            ),
          );
          Navigator.pop(context);
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
    final backgroundPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.65)
      ..style = PaintingStyle.fill;

    final path = Path()..addRect(Rect.fromLTWH(0, 0, size.width, size.height));

    final RRect rrect = RRect.fromRectAndRadius(
      rect,
      const Radius.circular(20),
    );
    final cutoutPath = Path()..addRRect(rrect);

    final finalPath = Path.combine(PathOperation.difference, path, cutoutPath);
    canvas.drawPath(finalPath, backgroundPaint);

    final borderPaint = Paint()
      ..color = isAligned ? AppTheme.neonGreen : Colors.orangeAccent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.5;

    final glowPaint = Paint()
      ..color = (isAligned ? AppTheme.neonGreen : Colors.orangeAccent)
          .withValues(alpha: 0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 10.0
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6.0);

    canvas.drawRRect(rrect, glowPaint);
    canvas.drawRRect(rrect, borderPaint);

    final bracketPaint = Paint()
      ..color = isAligned ? AppTheme.neonGreen : Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5.0
      ..strokeCap = StrokeCap.round;

    const double length = 25.0;

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