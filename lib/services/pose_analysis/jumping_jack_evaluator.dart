import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import '../../core/utils/pose_math.dart';
import 'base_pose_evaluator.dart';
import 'pose_analysis_result.dart';

class JumpingJackEvaluator extends BasePoseEvaluator {
  String _motionState = 'NEUTRAL';
  final double _landmarkConfidenceThreshold = 0.55;

  @override
  void reset() {
    _motionState = 'NEUTRAL';
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
    final rightShoulder = pose.landmarks[PoseLandmarkType.rightShoulder];
    final leftWrist = pose.landmarks[PoseLandmarkType.leftWrist];
    final rightWrist = pose.landmarks[PoseLandmarkType.rightWrist];
    final leftAnkle = pose.landmarks[PoseLandmarkType.leftAnkle];
    final rightAnkle = pose.landmarks[PoseLandmarkType.rightAnkle];

    if (_isLandmarkVisible(leftShoulder) &&
        _isLandmarkVisible(rightShoulder) &&
        _isLandmarkVisible(leftWrist) &&
        _isLandmarkVisible(rightWrist) &&
        _isLandmarkVisible(leftAnkle) &&
        _isLandmarkVisible(rightAnkle)) {

      double shoulderWidth = PoseMath.calculateDistance(leftShoulder!, rightShoulder!);
      double feetDistance = PoseMath.calculateDistance(leftAnkle!, rightAnkle!);
      double feetRatio = feetDistance / shoulderWidth;

      // ML Kit có gốc tọa độ Y hướng xuống dưới: Cổ tay cao hơn vai thì wrist.y < shoulder.y
      bool leftArmUp = leftWrist!.y < leftShoulder.y;
      bool rightArmUp = rightWrist!.y < rightShoulder.y;
      bool armsAreUp = leftArmUp && rightArmUp;
      bool armsAreDown = (leftWrist.y > leftShoulder.y + 50) && (rightWrist.y > rightShoulder.y + 50);

      bool feetAreWide = feetRatio > 1.55;
      bool feetAreClosed = feetRatio < 1.25;

      // Đánh giá tư thế lỗi thời gian thực
      if (feetAreWide && !armsAreUp) {
        isPostureCorrect = false;
        isArmsCorrect = false;
        feedback = 'Vung tay cao hơn qua đầu!';
      } else if (armsAreUp && !feetAreWide) {
        isPostureCorrect = false;
        isLegsCorrect = false;
        feedback = 'Nhảy dạng chân rộng ra hơn!';
      }

      // Thuật toán đếm lần
      if (_motionState == 'NEUTRAL') {
        if (feetAreWide && armsAreUp) {
          _motionState = 'ACTIVE'; // Đạt vị trí đỉnh nhảy
        }
      } else if (_motionState == 'ACTIVE') {
        if (feetAreClosed && armsAreDown) {
          _motionState = 'NEUTRAL'; // Về lại vị trí chuẩn
          shouldCountRep = true;
        }
      }

      if (isPostureCorrect) {
        if (_motionState == 'ACTIVE') {
          feedback = 'Tốt! Nhảy khép chân và hạ tay.';
        } else {
          feedback = 'Nhảy mở rộng chân và vung tay cao qua đầu.';
        }
      }
    } else {
      feedback = 'Đứng lùi xa ra để camera thấy từ đầu đến chân.';
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
