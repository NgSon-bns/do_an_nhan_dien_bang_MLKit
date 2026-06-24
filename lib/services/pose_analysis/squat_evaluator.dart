import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import '../../core/utils/pose_math.dart';
import 'base_pose_evaluator.dart';
import 'pose_analysis_result.dart';

class SquatEvaluator extends BasePoseEvaluator {
  String _motionState = 'UP';
  final double _landmarkConfidenceThreshold = 0.55;
  bool _isPostureCorrectInCurrentRep = true;
  int _reps = 0;

  // Biến lưu trữ mốc khi đứng thẳng
  double? _standingHipY;
  
  // Bộ lọc nhiễu khung hình
  int _errorFrames = 0;
  final int _maxAllowedErrorFrames = 5;

  @override
  void reset() {
    _motionState = 'UP';
    _isPostureCorrectInCurrentRep = true;
    _standingHipY = null;
    _errorFrames = 0;
    _reps = 0;
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
    if (kneeAngle > 160) {
      _standingHipY = currentHipY;
    }

    // 3. Kiểm tra tư thế lưng với bộ lọc nhiễu
    bool isCurrentPostureCorrect = true;
    if (_isLandmarkVisible(rightShoulder) && _isLandmarkVisible(rightHip)) {
      double backLeanAngle = PoseMath.calculateAngleToVertical(rightShoulder!, rightHip);
      if (backLeanAngle > 45) {
        isCurrentPostureCorrect = false;
        feedback = 'Giữ lưng thẳng, đừng đổ người quá nhiều!';
      }
    }

    // Cập nhật bộ lọc lỗi
    if (!isCurrentPostureCorrect) {
      _errorFrames++;
    } else {
      _errorFrames = 0; // Reset khi tư thế đúng trở lại
    }

    // Áp dụng bộ lọc: chỉ đánh dấu sai nếu vi phạm liên tiếp 5 khung hình
    if (_errorFrames > _maxAllowedErrorFrames) {
      isPostureCorrect = false;
      if (_motionState == 'DOWN') _isPostureCorrectInCurrentRep = false;
    }

    // 4. Logic Squat kết hợp (Góc gối + Độ hạ hông)
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
          _reps++;
          feedback = 'Tuyệt vời!';
        } else {
          isPostureCorrect = false;
          feedback = 'Lần tập không được tính do sai tư thế!';
        }
        _isPostureCorrectInCurrentRep = true;
      }
    }

    // Nếu tập đúng: từ rep thứ 2 trở đi chỉ hiển thị trạng thái tập đúng, rep đầu tiên vẫn giữ hướng dẫn chi tiết
    if (isPostureCorrect) {
      if (shouldCountRep) {
        feedback = "Tuyệt vời! Hoàn thành rep $_reps.";
      } else if (_reps > 0) {
        feedback = "Bạn đang tập đúng!";
      }
    }

    return PoseAnalysisResult(
      isPostureCorrect: isPostureCorrect,
      feedbackMessage: feedback,
      isBackCorrect: _errorFrames <= _maxAllowedErrorFrames,
      isLegsCorrect: true,
      isArmsCorrect: true,
      shouldCountRep: shouldCountRep,
    );
  }
}