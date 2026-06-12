import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import '../../core/utils/pose_math.dart';
import 'base_pose_evaluator.dart';
import 'pose_analysis_result.dart';

class PushUpEvaluator extends BasePoseEvaluator {
  String _motionState = 'UP';
  final double _landmarkConfidenceThreshold = 0.55;
  bool _isPostureCorrectInCurrentRep = true;

  @override
  void reset() {
    _motionState = 'UP';
    _isPostureCorrectInCurrentRep = true;
  }

  bool _isLandmarkVisible(PoseLandmark? landmark) {
    return landmark != null && landmark.likelihood > _landmarkConfidenceThreshold;
  }

  @override
  PoseAnalysisResult evaluate(Pose pose) {
    bool isPostureCorrect = true;
    String feedback = 'Đang làm tốt lắm! Hãy tiếp tục.';
    bool isBackCorrect = true;
    bool isLegsCorrect = true;
    bool isArmsCorrect = true;
    bool shouldCountRep = false;

    final leftShoulder = pose.landmarks[PoseLandmarkType.leftShoulder];
    final leftElbow = pose.landmarks[PoseLandmarkType.leftElbow];
    final leftWrist = pose.landmarks[PoseLandmarkType.leftWrist];

    final rightShoulder = pose.landmarks[PoseLandmarkType.rightShoulder];
    final rightElbow = pose.landmarks[PoseLandmarkType.rightElbow];
    final rightWrist = pose.landmarks[PoseLandmarkType.rightWrist];

    final rightHip = pose.landmarks[PoseLandmarkType.rightHip];
    final rightKnee = pose.landmarks[PoseLandmarkType.rightKnee];

    // Lựa chọn góc khuỷu tay của bên hiển thị rõ hơn trước camera
    double? elbowAngle;
    if (_isLandmarkVisible(rightShoulder) && _isLandmarkVisible(rightElbow) && _isLandmarkVisible(rightWrist)) {
      elbowAngle = PoseMath.calculateAngle(rightShoulder!, rightElbow!, rightWrist!);
    } else if (_isLandmarkVisible(leftShoulder) && _isLandmarkVisible(leftElbow) && _isLandmarkVisible(leftWrist)) {
      elbowAngle = PoseMath.calculateAngle(leftShoulder!, leftElbow!, leftWrist!);
    }

    if (elbowAngle != null) {
      // A. Phân tích lỗi lưng cong hoặc võng hông (dùng góc Vai - Hông - Đầu gối)
      if (_isLandmarkVisible(rightShoulder) && _isLandmarkVisible(rightHip) && _isLandmarkVisible(rightKnee)) {
        double backAngle = PoseMath.calculateAngle(rightShoulder!, rightHip!, rightKnee!);
        if (backAngle < 160) {
          isPostureCorrect = false;
          isBackCorrect = false;
          feedback = 'Hạ hông xuống, giữ lưng thẳng!';
        } else if (backAngle > 195) {
          isPostureCorrect = false;
          isBackCorrect = false;
          feedback = 'Nâng hông lên, gồng cơ bụng!';
        }
      }

      // Nếu phát hiện lỗi tư thế trong khi đang chống đẩy (không ở trạng thái đẩy thẳng tay)
      if (!isPostureCorrect && (elbowAngle < 155 || _motionState == 'DOWN')) {
        _isPostureCorrectInCurrentRep = false;
      }

      // B. Đếm số lần dựa trên góc khuỷu tay
      if (elbowAngle < 90) {
        if (_motionState == 'UP') {
          _motionState = 'DOWN'; // Đã xuống sâu
        }
      } else if (elbowAngle > 155) {
        if (_motionState == 'DOWN') {
          _motionState = 'UP'; // Đã đẩy thẳng lên
          if (_isPostureCorrectInCurrentRep) {
            shouldCountRep = true;
          } else {
            feedback = 'Lần tập không được tính do sai tư thế!';
          }
          _isPostureCorrectInCurrentRep = true; // Reset cho rep tiếp theo
        }
      }

      if (isPostureCorrect && _motionState == 'DOWN') {
        feedback = 'Giữ lưng thẳng khi hạ xuống!';
      } else if (isPostureCorrect && _motionState == 'UP') {
        feedback = 'Hạ người xuống dưới 90 độ khuỷu tay.';
      }
    } else {
      feedback = 'Hãy nghiêng người sang một bên để AI nhìn thấy khuỷu tay.';
    }

    return PoseAnalysisResult(
      isPostureCorrect: isPostureCorrect,
      feedbackMessage: feedback,
      isBackCorrect: isBackCorrect,
      isLegsCorrect: isLegsCorrect,
      isArmsCorrect: isArmsCorrect,
      shouldCountRep: shouldCountRep,
    );
  }
}
