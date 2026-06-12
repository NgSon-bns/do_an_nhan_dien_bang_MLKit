import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import '../../core/utils/pose_math.dart';
import 'base_pose_evaluator.dart';
import 'pose_analysis_result.dart';

class PlankEvaluator extends BasePoseEvaluator {
  final double _landmarkConfidenceThreshold = 0.55;

  @override
  void reset() {}

  bool _isLandmarkVisible(PoseLandmark? landmark) {
    return landmark != null &&
        landmark.likelihood > _landmarkConfidenceThreshold;
  }

  @override
  PoseAnalysisResult evaluate(Pose pose) {
    bool isPostureCorrect = true;
    String feedback = 'Tư thế tuyệt vời! Hãy duy trì gồng bụng.';
    bool isBackCorrect = true;
    bool isLegsCorrect = true;
    bool isArmsCorrect = true;

    // 1. Kiểm tra độ tin cậy của từng bên
    bool isRightSideVisible =
        _isLandmarkVisible(pose.landmarks[PoseLandmarkType.rightShoulder]) &&
        _isLandmarkVisible(pose.landmarks[PoseLandmarkType.rightElbow]) &&
        _isLandmarkVisible(pose.landmarks[PoseLandmarkType.rightHip]) &&
        _isLandmarkVisible(pose.landmarks[PoseLandmarkType.rightAnkle]) &&
        _isLandmarkVisible(pose.landmarks[PoseLandmarkType.rightWrist]);

    bool isLeftSideVisible =
        _isLandmarkVisible(pose.landmarks[PoseLandmarkType.leftShoulder]) &&
        _isLandmarkVisible(pose.landmarks[PoseLandmarkType.leftElbow]) &&
        _isLandmarkVisible(pose.landmarks[PoseLandmarkType.leftHip]) &&
        _isLandmarkVisible(pose.landmarks[PoseLandmarkType.leftAnkle]) &&
        _isLandmarkVisible(pose.landmarks[PoseLandmarkType.leftWrist]);

    // 2. Chọn bên để đánh giá
    // Ưu tiên bên phải, nếu không rõ thì lấy bên trái
    final bool useRightSide = isRightSideVisible;
    final bool useLeftSide = !isRightSideVisible && isLeftSideVisible;

    if (useRightSide || useLeftSide) {
      final shoulder = useRightSide
          ? pose.landmarks[PoseLandmarkType.rightShoulder]!
          : pose.landmarks[PoseLandmarkType.leftShoulder]!;
      final elbow = useRightSide
          ? pose.landmarks[PoseLandmarkType.rightElbow]!
          : pose.landmarks[PoseLandmarkType.leftElbow]!;
      final hip = useRightSide
          ? pose.landmarks[PoseLandmarkType.rightHip]!
          : pose.landmarks[PoseLandmarkType.leftHip]!;
      final ankle = useRightSide
          ? pose.landmarks[PoseLandmarkType.rightAnkle]!
          : pose.landmarks[PoseLandmarkType.leftAnkle]!;
      final wrist = useRightSide
          ? pose.landmarks[PoseLandmarkType.rightWrist]!
          : pose.landmarks[PoseLandmarkType.leftWrist]!;

      // 3. Tính toán góc
      // Góc khuỷu tay: Vai - Khuỷu - cổ tay (để đảm bảo khuỷu tay dưới vai)
      double elbowAngle = PoseMath.getElbowAngle(shoulder, elbow, wrist);
      // Góc thân người: Vai - Hông - Gót chân
      double bodyLineAngle;
      if(shoulder.x < hip.x) {
        bodyLineAngle = PoseMath.calculateAngle(shoulder, hip, ankle);
      } else {
        bodyLineAngle = PoseMath.calculateAngle(ankle, hip, shoulder);
      }

      // 4. Logic đánh giá
      if (elbowAngle < (useRightSide?70:250 )|| elbowAngle > (useRightSide?110:300)) {
        isPostureCorrect = false;
        isArmsCorrect = false;
        feedback = 'Đặt cẳng tay lên sàn, khuỷu tay vuông góc ngay dưới vai.';
      } else if (bodyLineAngle <170 ) {
        isPostureCorrect = false;
        isBackCorrect = false;
        feedback = 'Thân người bị võng, hãy siết chặt cơ bụng!';
      } else if (bodyLineAngle > 195) {
        isPostureCorrect = false;
        isBackCorrect = false;
        feedback = 'Hông quá cao, hãy hạ thấp người xuống cho thẳng hàng!';
      }
    } else {
      isPostureCorrect = false;
      feedback =
          'Vui lòng nằm nghiêng để camera thấy rõ vai, khuỷu tay, hông và gót chân.';
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
