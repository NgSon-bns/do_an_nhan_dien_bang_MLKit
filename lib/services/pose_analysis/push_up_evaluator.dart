import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import '../../core/utils/pose_math.dart';
import 'base_pose_evaluator.dart';
import 'pose_analysis_result.dart';

class PushUpEvaluator extends BasePoseEvaluator {
  String _motionState = 'UP';
  final double _landmarkConfidenceThreshold = 0.55;
  bool _isPostureCorrectInCurrentRep = true;
  bool _isRightSideVisible = true;

  double _standingShoulderY = 0; // Mốc để so sánh độ sâu
  int _errorFrames = 0; // Bộ lọc nhiễu khung hình
  bool isBackCorrect = true;

  @override
  void reset() {
    _motionState = 'UP';
    _isPostureCorrectInCurrentRep = true;
    _standingShoulderY = 0;
    _errorFrames = 0;
    isBackCorrect = true;
  }

  bool _isLandmarkVisible(PoseLandmark? landmark) {
    return landmark != null &&
        landmark.likelihood > _landmarkConfidenceThreshold;
  }

  @override
  PoseAnalysisResult evaluate(Pose pose) {
    bool isPostureCorrect = true;
    String feedback = 'Đang làm tốt lắm! Hãy tiếp tục.';
    bool shouldCountRep = false;

    // Lấy landmark
    final leftShoulder = pose.landmarks[PoseLandmarkType.leftShoulder];
    final leftElbow = pose.landmarks[PoseLandmarkType.leftElbow];
    final leftWrist = pose.landmarks[PoseLandmarkType.leftWrist];
    final rightShoulder = pose.landmarks[PoseLandmarkType.rightShoulder];
    final rightElbow = pose.landmarks[PoseLandmarkType.rightElbow];
    final rightWrist = pose.landmarks[PoseLandmarkType.rightWrist];
    final rightHip = pose.landmarks[PoseLandmarkType.rightHip];
    final leftHip = pose.landmarks[PoseLandmarkType.leftHip];
    final rightKnee = pose.landmarks[PoseLandmarkType.rightKnee];
    final leftKnee = pose.landmarks[PoseLandmarkType.leftKnee];

    if (!_isLandmarkVisible(rightShoulder) ||
        !_isLandmarkVisible(rightHip) ||
        !_isLandmarkVisible(rightWrist)) {
      return PoseAnalysisResult(
        isPostureCorrect: false,
        feedbackMessage: 'Cần nhìn thấy vai, hông và cổ tay của bạn',
      );
    }

    // 1. Xác định góc khuỷu tay
    double? elbowAngle;
    if ((rightShoulder!.x < rightHip!.x) &&
        _isLandmarkVisible(rightShoulder) &&
        _isLandmarkVisible(rightElbow) &&
        _isLandmarkVisible(rightWrist)) {
      elbowAngle = PoseMath.getElbowAngle(
        rightShoulder!,
        rightElbow!,
        rightWrist!,
      );
      _isRightSideVisible = true;
    } else if ((leftShoulder!.x > leftHip!.x) &&
        _isLandmarkVisible(leftShoulder) &&
        _isLandmarkVisible(leftElbow) &&
        _isLandmarkVisible(leftWrist)) {
      elbowAngle = PoseMath.getElbowAngle(
        leftShoulder!,
        leftElbow!,
        leftWrist!,
      );
      _isRightSideVisible = false;
    }

    if (elbowAngle == null)
      return PoseAnalysisResult(
        isPostureCorrect: false,
        feedbackMessage: 'Hãy nghiêng người để camera thấy rõ khuỷu tay',
      );

    // 2. Calibrate mốc (Khi tay thẳng, lấy vị trí hông làm gốc)
    // Thay đổi phần tính currentShoulderY
    double currentShoulderY = 1;
    if (elbowAngle < 110) {
      _standingShoulderY = currentShoulderY;
    }
    // Khi tay thẳng, lưu lại mốc của ĐÚNG BÊN ĐÓ
    if (elbowAngle > 160) {
      currentShoulderY = _isRightSideVisible
          ? rightShoulder!.y
          : leftShoulder!.y;
    }

    // 3. Phân tích tư thế lưng
    double backAngle = (rightShoulder!.x > rightHip!.x)
        ? PoseMath.calculateAngle(
            (_isRightSideVisible ? rightShoulder! : leftShoulder!),
            (_isRightSideVisible ? rightHip! : leftHip!),
            (_isRightSideVisible ? rightKnee! : leftKnee!),
          )
        : PoseMath.calculateAngle(
            (_isRightSideVisible ? rightKnee! : leftKnee!),
            (_isRightSideVisible ? rightHip! : leftHip!),
            (_isRightSideVisible ? rightShoulder! : leftShoulder!),
          );
    if (backAngle < 160 || backAngle > 195) {
      isPostureCorrect = false;
      feedback = 'Giữ vai hông và chân thẳng hàng!';
      print('Back Angle: $backAngle $_isRightSideVisible');
    } else {
      isBackCorrect = true;
    }

    // 4. Lọc nhiễu tư thế
    if (!isPostureCorrect) {
      _errorFrames++;
      if (_errorFrames > 3) {
        _isPostureCorrectInCurrentRep = false;
        isBackCorrect = false;
      }
    } else {
      _errorFrames = 0;
    }

    // Khi kiểm tra độ sâu, so sánh với mốc của ĐÚNG BÊN ĐÓ
    bool isPushUpDeepEnough = (currentShoulderY < _standingShoulderY! + 0.05);

    if (elbowAngle < 110) {
      if (_motionState == 'UP') {
        _motionState = 'DOWN';
        _isPostureCorrectInCurrentRep = true;
        print(
          'down Elbow Angle: $elbowAngle, Back Angle: $backAngle, Shoulder Y: $currentShoulderY, Standing Shoulder Y: $_standingShoulderY, Error Frames: $_errorFrames, Is Posture Correct: $_isPostureCorrectInCurrentRep, Is PushUp Deep Enough: $isPushUpDeepEnough,shouldCountRep: $shouldCountRep',
        ); // Reset trạng thái khi bắt đầu xuống
      }
    } else if (elbowAngle > 150) {
      if (_motionState == 'DOWN') {
        _motionState = 'UP';
        if (_isPostureCorrectInCurrentRep && isPushUpDeepEnough) {
          shouldCountRep = true;
          feedback = 'Tuyệt vời!';
        }
        print(
          'up Elbow Angle: $elbowAngle, Back Angle: $backAngle, Shoulder Y: $currentShoulderY, Standing Shoulder Y: $_standingShoulderY, Error Frames: $_errorFrames, Is Posture Correct: $_isPostureCorrectInCurrentRep, Is PushUp Deep Enough: $isPushUpDeepEnough,shouldCountRep: $shouldCountRep',
        );
      }
    }

    return PoseAnalysisResult(
      isPostureCorrect: isPostureCorrect,
      feedbackMessage: feedback,
      isBackCorrect: true,
      isLegsCorrect: true,
      isArmsCorrect: true,
      shouldCountRep: shouldCountRep,
    );
  }
}
