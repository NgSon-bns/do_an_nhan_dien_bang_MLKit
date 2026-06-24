
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

import 'base_pose_evaluator.dart';
import 'pose_analysis_result.dart';
import '../../core/utils/pose_math.dart';
enum BurpeeState { STAND, SQUAT, PLANK, RETURN, JUMP }

class BurpeeEvaluator extends BasePoseEvaluator {
  BurpeeState _currentState = BurpeeState.STAND;
  int _reps = 0;
  
  // Biến hỗ trợ chống rung (Debounce)
  int _stableFrames = 0;
  final int _requiredStableFrames = 2; // Yêu cầu ổn định 5 khung hình

  @override
  PoseAnalysisResult evaluate(Pose pose) {
    final hip = pose.landmarks[PoseLandmarkType.rightHip];
    final knee = pose.landmarks[PoseLandmarkType.rightKnee];
    final shoulder = pose.landmarks[PoseLandmarkType.rightShoulder];
    final ankle = pose.landmarks[PoseLandmarkType.rightAnkle];

    if (hip == null || knee == null || shoulder == null || ankle == null) {
      return PoseAnalysisResult(isPostureCorrect: false, feedbackMessage: "Hãy đứng lùi lại...");
    }

    double kneeAngle = PoseMath.getElbowAngle(hip, knee, ankle);
    double hipAngle = PoseMath.getElbowAngle(shoulder, hip, knee);

    bool shouldCountRep = false;
    String feedback = "Đang thực hiện...";
    bool isPostureCorrect = true;
    print("State: $_currentState | Stable: $_stableFrames | Knee: ${kneeAngle.toStringAsFixed(1)} | Hip: ${hipAngle.toStringAsFixed(1)}");
    // Logic kiểm tra và chuyển trạng thái với bộ lọc ổn định
    switch (_currentState) {
      case BurpeeState.STAND:
        if (kneeAngle < 100) _incrementStableFrames(BurpeeState.SQUAT);
        print("State: $_currentState | Stable: $_stableFrames | Knee: ${kneeAngle.toStringAsFixed(1)} | Hip: ${hipAngle.toStringAsFixed(1)}");
    
      case BurpeeState.SQUAT:
        if (hipAngle > 140) _incrementStableFrames(BurpeeState.PLANK);
        print("State: $_currentState | Stable: $_stableFrames | Knee: ${kneeAngle.toStringAsFixed(1)} | Hip: ${hipAngle.toStringAsFixed(1)}");
    
      case BurpeeState.PLANK:
        if (hipAngle < 120) _incrementStableFrames(BurpeeState.RETURN);
        print("State: $_currentState | Stable: $_stableFrames | Knee: ${kneeAngle.toStringAsFixed(1)} | Hip: ${hipAngle.toStringAsFixed(1)}");
    
      case BurpeeState.RETURN:
        if (kneeAngle > 160) _incrementStableFrames(BurpeeState.JUMP);
        print("State: $_currentState | Stable: $_stableFrames | Knee: ${kneeAngle.toStringAsFixed(1)} | Hip: ${hipAngle.toStringAsFixed(1)}");
    
      case BurpeeState.JUMP:
        if (kneeAngle > 165) {
          _reps++;
          shouldCountRep = true; // Chỉ trả về true đúng 1 lần tại đây
          feedback = "Hoàn thành rep $_reps!";
          _currentState = BurpeeState.STAND;
        }
        print("State: $_currentState | Stable: $_stableFrames | Knee: ${kneeAngle.toStringAsFixed(1)} | Hip: ${hipAngle.toStringAsFixed(1)}");
    
    }

    return PoseAnalysisResult(
      isPostureCorrect: isPostureCorrect,
      feedbackMessage: feedback,
      shouldCountRep: shouldCountRep,
    );
  }

  // Phương thức hỗ trợ để chống rung chuyển trạng thái
  void _incrementStableFrames(BurpeeState nextState) {
    
      _currentState = nextState;
      
  }

  @override
  void reset() {
    _currentState = BurpeeState.STAND;
    _reps = 0;
    _stableFrames = 0;
  }
}