import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import '../../core/utils/pose_math.dart';
import 'base_pose_evaluator.dart';
import 'pose_analysis_result.dart';

class SquatEvaluator extends BasePoseEvaluator {
  String _motionState = 'UP';
  final double _landmarkConfidenceThreshold = 0.55;

  @override
  void reset() {
    _motionState = 'UP';
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

    final leftHip = pose.landmarks[PoseLandmarkType.leftHip];
    final leftKnee = pose.landmarks[PoseLandmarkType.leftKnee];
    final leftAnkle = pose.landmarks[PoseLandmarkType.leftAnkle];

    final rightShoulder = pose.landmarks[PoseLandmarkType.rightShoulder];
    final rightHip = pose.landmarks[PoseLandmarkType.rightHip];
    final rightKnee = pose.landmarks[PoseLandmarkType.rightKnee];
    final rightAnkle = pose.landmarks[PoseLandmarkType.rightAnkle];

    // Lựa chọn góc gối của bên nhìn rõ hơn
    double? kneeAngle;
    if (_isLandmarkVisible(rightHip) && _isLandmarkVisible(rightKnee) && _isLandmarkVisible(rightAnkle)) {
      kneeAngle = PoseMath.calculateAngle(rightHip!, rightKnee!, rightAnkle!);
    } else if (_isLandmarkVisible(leftHip) && _isLandmarkVisible(leftKnee) && _isLandmarkVisible(leftAnkle)) {
      kneeAngle = PoseMath.calculateAngle(leftHip!, leftKnee!, leftAnkle!);
    }

    if (kneeAngle != null) {
      // A. Kiểm tra tư thế lưng nghiêng quá sâu về trước (Vai - Hông so với trục dọc)
      if (_isLandmarkVisible(rightShoulder) && _isLandmarkVisible(rightHip)) {
        double backLeanAngle = PoseMath.calculateAngleToVertical(rightShoulder!, rightHip!);
        if (backLeanAngle > 45) {
          isPostureCorrect = false;
          isBackCorrect = false;
          feedback = 'Giữ ngực cao và thẳng lưng lên!';
        }
      }

      // B. Đếm số lần squat
      if (kneeAngle < 100) {
        if (_motionState == 'UP') {
          _motionState = 'DOWN'; // Đã ngồi sâu
        }
      } else if (kneeAngle > 155) {
        if (_motionState == 'DOWN') {
          _motionState = 'UP'; // Đứng thẳng
          shouldCountRep = true;
        }
      }

      // Phản hồi hỗ trợ sâu hơn
      if (isPostureCorrect) {
        if (_motionState == 'DOWN') {
          feedback = 'Tốt! Giữ thăng bằng và đứng thẳng dậy.';
        } else {
          feedback = 'Hạ hông sâu xuống dưới song song đùi.';
        }
      }
    } else {
      feedback = 'Hãy quay người góc nghiêng để camera thấy rõ gối và hông.';
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
