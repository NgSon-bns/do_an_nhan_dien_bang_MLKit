import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import '../../core/utils/pose_math.dart';
import 'base_pose_evaluator.dart';
import 'pose_analysis_result.dart';

class PlankEvaluator extends BasePoseEvaluator {
  final double _landmarkConfidenceThreshold = 0.55;

  @override
  void reset() {
    // Plank không cần biến trạng thái đếm reps vì tính theo thời gian giữ tư thế
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

    final rightShoulder = pose.landmarks[PoseLandmarkType.rightShoulder];
    final rightHip = pose.landmarks[PoseLandmarkType.rightHip];
    final rightKnee = pose.landmarks[PoseLandmarkType.rightKnee];
    final rightAnkle = pose.landmarks[PoseLandmarkType.rightAnkle];

    final leftShoulder = pose.landmarks[PoseLandmarkType.leftShoulder];
    final leftHip = pose.landmarks[PoseLandmarkType.leftHip];
    final leftKnee = pose.landmarks[PoseLandmarkType.leftKnee];
    final leftAnkle = pose.landmarks[PoseLandmarkType.leftAnkle];

    // Lấy dữ liệu bên rõ hơn
    PoseLandmark? shoulder = _isLandmarkVisible(rightShoulder) ? rightShoulder : leftShoulder;
    PoseLandmark? hip = _isLandmarkVisible(rightHip) ? rightHip : leftHip;
    PoseLandmark? knee = _isLandmarkVisible(rightKnee) ? rightKnee : leftKnee;
    PoseLandmark? ankle = _isLandmarkVisible(rightAnkle) ? rightAnkle : leftAnkle;

    if (_isLandmarkVisible(shoulder) && _isLandmarkVisible(hip) && _isLandmarkVisible(knee)) {
      // A. Đo góc thẳng của lưng (Vai - Hông - Gối)
      double hipAngle = PoseMath.calculateAngle(shoulder!, hip!, knee!);
      
      // B. Đo góc nằm ngang của toàn bộ cơ thể
      double horizontalAngle = 0.0;
      if (_isLandmarkVisible(ankle)) {
        horizontalAngle = PoseMath.calculateAngleToHorizontal(shoulder, ankle!);
      }

      if (hipAngle < 165) {
        isPostureCorrect = false;
        isBackCorrect = false;
        feedback = 'Hạ hông xuống thấp một chút!';
      } else if (hipAngle > 195) {
        isPostureCorrect = false;
        isBackCorrect = false;
        feedback = 'Nâng hông lên cao, siết chặt cơ bụng!';
      } else if (horizontalAngle > 25) {
        isPostureCorrect = false;
        feedback = 'Giữ thân người nằm ngang song song mặt sàn!';
      } else {
        feedback = 'Tư thế tuyệt vời! Hãy duy trì gồng bụng.';
      }
    } else {
      feedback = 'Nằm nghiêng trước camera để thấy được vai, hông và đầu gối.';
    }

    return PoseAnalysisResult(
      isPostureCorrect: isPostureCorrect,
      feedbackMessage: feedback,
      isBackCorrect: isBackCorrect,
      isLegsCorrect: isLegsCorrect,
      isArmsCorrect: isArmsCorrect,
      shouldCountRep: false,
    );
  }
}
