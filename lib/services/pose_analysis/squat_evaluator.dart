import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import '../../core/utils/pose_math.dart';
import 'base_pose_evaluator.dart';
import 'pose_analysis_result.dart';

class SquatEvaluator extends BasePoseEvaluator {
  String _motionState = 'UP';
  final double _landmarkConfidenceThreshold = 0.55;
  bool _isPostureCorrectInCurrentRep = true;

  // Biến lưu trữ mốc khi đứng thẳng
  double? _standingHipY;

  @override
  void reset() {
    _motionState = 'UP';
    _isPostureCorrectInCurrentRep = true;
    _standingHipY = null;
  }

  bool _isLandmarkVisible(PoseLandmark? landmark) {
    return landmark != null && landmark.likelihood > _landmarkConfidenceThreshold;
  }

  @override
  PoseAnalysisResult evaluate(Pose pose) {
    String feedback = 'Đang làm tốt lắm!';
    bool isPostureCorrect = true;
    bool shouldCountRep = false;

    final leftHip = pose.landmarks[PoseLandmarkType.leftHip];
    final rightHip = pose.landmarks[PoseLandmarkType.rightHip];
    final rightKnee = pose.landmarks[PoseLandmarkType.rightKnee];
    final rightAnkle = pose.landmarks[PoseLandmarkType.rightAnkle];
    final rightShoulder = pose.landmarks[PoseLandmarkType.rightShoulder];

    if (!_isLandmarkVisible(leftHip) || !_isLandmarkVisible(rightHip) || 
        !_isLandmarkVisible(rightKnee) || !_isLandmarkVisible(rightAnkle)) {
      return PoseAnalysisResult(isPostureCorrect: false, feedbackMessage: 'Điều chỉnh tư thế để thấy rõ hông và chân.');
    }

    // 1. Tính toán vị trí hiện tại
    double currentHipY = (leftHip!.y + rightHip!.y) / 2;
    double kneeAngle = PoseMath.getElbowAngle(rightHip, rightKnee!, rightAnkle!);

    // 2. Thiết lập mốc đứng thẳng (Calibrate)
    // Nếu góc gối lớn (>160), coi là đang đứng yên -> lưu lại độ cao hông làm mốc
    if (kneeAngle > 160) {
      _standingHipY = currentHipY;
    }

    // 3. Kiểm tra tư thế lưng
    if (_isLandmarkVisible(rightShoulder) && _isLandmarkVisible(rightHip)) {
      double backLeanAngle = PoseMath.calculateAngleToVertical(rightShoulder!, rightHip);
      if (backLeanAngle > 45) {
        isPostureCorrect = false;
        feedback = 'Giữ lưng thẳng, đừng đổ người quá nhiều!';
        if (_motionState == 'DOWN') _isPostureCorrectInCurrentRep = false;
      }
    }

    // 4. Logic Squat kết hợp (Góc gối + Độ hạ hông)
    // Ngưỡng hạ hông: cần thấp hơn mốc đứng thẳng một khoảng (ví dụ 0.1 đơn vị tỷ lệ)
    bool isSquattingDeepEnough = _standingHipY != null && (currentHipY - _standingHipY!) > PoseMath.calculateDistance(rightHip, rightKnee)*0.7 ;

    if (kneeAngle < 110 && isSquattingDeepEnough) {
      if (_motionState == 'UP') {
        _motionState = 'DOWN';
      }
    } else if (kneeAngle > 150) {
      if (_motionState == 'DOWN') {
        _motionState = 'UP';
        if (_isPostureCorrectInCurrentRep) {
          shouldCountRep = true;
          feedback = 'Tuyệt vời!';
        } else {
          
        }
        _isPostureCorrectInCurrentRep = true;
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