import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import '../../core/utils/pose_math.dart';
import 'base_pose_evaluator.dart';
import 'pose_analysis_result.dart';

class PlankEvaluator extends BasePoseEvaluator {
  final double _landmarkConfidenceThreshold = 0.55;

  // Bộ lọc nhiễu
  int _errorFrames = 0;
  final int _maxAllowedErrorFrames = 30; // Plank thường cần ngưỡng lọc cao hơn squat/pushup

  @override
  void reset() {
    _errorFrames = 0;
  }

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
    String feedbackErr = '';

    final bool useRightSide =
        (pose.landmarks[PoseLandmarkType.rightShoulder]?.x ??
            pose.landmarks[PoseLandmarkType.leftShoulder]?.x ??
            0) <
        (pose.landmarks[PoseLandmarkType.rightHip]?.x ??
            pose.landmarks[PoseLandmarkType.leftHip]?.x ??
            0);
    final bool useLeftSide = !useRightSide;

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
      double elbowAngle = PoseMath.getElbowAngle(shoulder, elbow, wrist);
      double bodyLineAngle = (shoulder.x < hip.x)
          ? PoseMath.calculateAngle(shoulder, hip, ankle)
          : PoseMath.calculateAngle(ankle, hip, shoulder);

      // 4. Kiểm tra tư thế (Cập nhật bộ lọc lỗi)
      bool isCurrentPostureCorrect = true;
      if (elbowAngle < 70 || elbowAngle > 120) {
        isCurrentPostureCorrect = false;
        feedbackErr =
            'Đặt cẳng tay lên sàn, khuỷu tay vuông góc ngay dưới vai.';
        isArmsCorrect = false;
      } else if (bodyLineAngle < 175) {
        isCurrentPostureCorrect = false;
        feedbackErr = 'Thân người bị võng, hãy siết chặt cơ bụng!';
        isBackCorrect = false;
      } else if (bodyLineAngle > 210) {
        isCurrentPostureCorrect = false;
        feedbackErr = 'Hông quá cao, hãy hạ thấp người xuống cho thẳng hàng!';
        isBackCorrect = false;
      }
      print("Body Line Angle: $bodyLineAngle $useRightSide $elbowAngle");
      // Logic bộ lọc nhiễu
      if (!isCurrentPostureCorrect) {
        _errorFrames++;
      } else {
        _errorFrames = 0;
      }

      if (_errorFrames > _maxAllowedErrorFrames) {
        isPostureCorrect = false;
        feedback = feedbackErr;
      }
    } else {
      isPostureCorrect = false;
      feedback =
          'Vui lòng nằm nghiêng để camera thấy rõ vai, khuỷu tay, hông và gót chân.';
    }

    // Nếu tập đúng: hiển thị câu khích lệ mặc định
    if (isPostureCorrect) {
      feedback = "Tư thế tuyệt vời! Hãy duy trì gồng bụng.";
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
