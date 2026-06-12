import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import '../../core/utils/pose_math.dart';
import 'base_pose_evaluator.dart';
import 'pose_analysis_result.dart';

class SquatEvaluator extends BasePoseEvaluator {
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

    final leftHip = pose.landmarks[PoseLandmarkType.leftHip];
    final leftKnee = pose.landmarks[PoseLandmarkType.leftKnee];
    final rightShoulder = pose.landmarks[PoseLandmarkType.rightShoulder];
    final rightHip = pose.landmarks[PoseLandmarkType.rightHip];
    final rightKnee = pose.landmarks[PoseLandmarkType.rightKnee];
    final rightAnkle = pose.landmarks[PoseLandmarkType.rightAnkle];

    // Kiểm tra độ ổn định của landmark trước khi tính toán
    if (!_isLandmarkVisible(leftHip) || !_isLandmarkVisible(rightHip) || 
        !_isLandmarkVisible(leftKnee) || !_isLandmarkVisible(rightKnee)) {
      return PoseAnalysisResult(
        isPostureCorrect: false,
        feedbackMessage: 'Hãy điều chỉnh tư thế để camera thấy rõ gối và hông.',
        isBackCorrect: true,
        isLegsCorrect: true,
        isArmsCorrect: true,
        shouldCountRep: false,
      );
    }

    // Tính góc gối
    double kneeAngle = PoseMath.getElbowAngle(rightHip!, rightKnee!, rightAnkle!);

    // Tính tỷ lệ gối/hông (kneeGap / hipGap)


    // 1. Cập nhật mốc _baseRatio khi đứng thẳng
    

    // 2. Kiểm tra tư thế lưng (nghiêng về trước)
    if (_isLandmarkVisible(rightShoulder) && _isLandmarkVisible(rightHip)) {
      double backLeanAngle = PoseMath.calculateAngleToVertical(rightShoulder!, rightHip);
      if (backLeanAngle > 45) {
        isPostureCorrect = false;
        isBackCorrect = false;
        feedback = 'Giữ ngực cao và thẳng lưng lên!';
      }
    }

    // Nếu phát hiện lỗi tư thế trong khi đang thực hiện squat (không đứng thẳng)
    if (!isPostureCorrect && (kneeAngle < 155 || _motionState == 'DOWN')) {
      _isPostureCorrectInCurrentRep = false;
    }

    // 3. Logic squat và phát hiện khép gối
    if (kneeAngle < 100) {
      if (_motionState == 'UP') _motionState = 'DOWN';
      
    } else if (kneeAngle > 155) {
      if (_motionState == 'DOWN') {
        _motionState = 'UP';
        if (_isPostureCorrectInCurrentRep) {
          shouldCountRep = true;
        } else {
          feedback = 'Lần tập không được tính do sai tư thế!';
        }
        _isPostureCorrectInCurrentRep = true; // Reset cho rep tiếp theo
      }
    }

    // Phản hồi bổ sung
    if (isPostureCorrect && _motionState == 'UP') {
      feedback = 'Hạ hông sâu xuống dưới song song đùi.';
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