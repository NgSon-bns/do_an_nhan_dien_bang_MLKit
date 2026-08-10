import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

import 'base_pose_evaluator.dart';
import 'pose_analysis_result.dart';
import 'package:demo/core/utils/pose_math.dart';

enum LungeState { stand, lunge }

class WalkingLungeEvaluator extends BasePoseEvaluator {
  LungeState _currentState = LungeState.stand;
  int _reps = 0;
  bool _isPostureCorrectInCurrentRep = true;
  final double _landmarkConfidenceThreshold = 0.55;

  @override
  void reset() {
    _currentState = LungeState.stand;
    _reps = 0;
    _isPostureCorrectInCurrentRep = true;
  }

  @override
  PoseAnalysisResult evaluate(Pose pose) {
    final leftShoulder = pose.landmarks[PoseLandmarkType.leftShoulder];
    final leftHip = pose.landmarks[PoseLandmarkType.leftHip];
    final leftKnee = pose.landmarks[PoseLandmarkType.leftKnee];
    final leftAnkle = pose.landmarks[PoseLandmarkType.leftAnkle];

    final rightShoulder = pose.landmarks[PoseLandmarkType.rightShoulder];
    final rightHip = pose.landmarks[PoseLandmarkType.rightHip];
    final rightKnee = pose.landmarks[PoseLandmarkType.rightKnee];
    final rightAnkle = pose.landmarks[PoseLandmarkType.rightAnkle];

    
    if (leftShoulder == null || leftHip == null || leftKnee == null || leftAnkle == null ||
        rightShoulder == null || rightHip == null || rightKnee == null || rightAnkle == null) {
      return PoseAnalysisResult(
        isPostureCorrect: false,
        feedbackMessage: "Hãy đứng lùi lại để camera thấy rõ gối và hông cả hai bên.",
        shouldCountRep: false,
      );
    }

    
    if (leftShoulder.likelihood < _landmarkConfidenceThreshold ||
        leftHip.likelihood < _landmarkConfidenceThreshold ||
        leftKnee.likelihood < _landmarkConfidenceThreshold ||
        leftAnkle.likelihood < _landmarkConfidenceThreshold ||
        rightShoulder.likelihood < _landmarkConfidenceThreshold ||
        rightHip.likelihood < _landmarkConfidenceThreshold ||
        rightKnee.likelihood < _landmarkConfidenceThreshold ||
        rightAnkle.likelihood < _landmarkConfidenceThreshold) {
      return PoseAnalysisResult(
        isPostureCorrect: false,
        feedbackMessage: "Hãy điều chỉnh tư thế để camera thấy rõ toàn bộ cơ thể.",
        shouldCountRep: false,
      );
    }

    
    double leftKneeAngle = PoseMath.getElbowAngle(leftHip, leftKnee, leftAnkle);
    double rightKneeAngle = PoseMath.getElbowAngle(rightHip, rightKnee, rightAnkle);

    
    double leftBackTilt = PoseMath.calculateAngleToVertical(leftShoulder, leftHip);
    double rightBackTilt = PoseMath.calculateAngleToVertical(rightShoulder, rightHip);
    double averageBackTilt = (leftBackTilt + rightBackTilt) / 2.0;

    bool isPostureCorrect = true;
    String feedback = "";
    bool shouldCountRep = false;

    
    if (averageBackTilt > 20.0) {
      isPostureCorrect = false;
      feedback = "Giữ ngực cao và thẳng lưng lên (độ nghiêng lưng < 20°)!";
    }

    
    if (!isPostureCorrect && _currentState == LungeState.lunge) {
      _isPostureCorrectInCurrentRep = false;
    }

    
    switch (_currentState) {
      case LungeState.stand:
        
        if (leftKneeAngle < 110 && rightKneeAngle < 110) {
          _currentState = LungeState.lunge;
          feedback = "Tấn tốt! Hãy đẩy gót chân đứng lên.";
        } else {
          feedback = "Hãy bước dài lên và hạ thấp hông xuống (góc hai gối < 110°).";
        }
        break;

      case LungeState.lunge:
        
        if (leftKneeAngle > 150 && rightKneeAngle > 150) {
          _currentState = LungeState.stand;
          if (_isPostureCorrectInCurrentRep) {
            _reps++;
            shouldCountRep = true;
            feedback = "Hoàn thành rep $_reps!";
          } else {
            isPostureCorrect = false;
            feedback = "Rep tập không được tính do gù/khom lưng quá 20°!";
          }
          _isPostureCorrectInCurrentRep = true; 
        } else {
          feedback = "Hãy đẩy người đứng thẳng dậy hoàn toàn.";
        }
        break;
    }

    
    if (isPostureCorrect) {
      if (shouldCountRep) {
        feedback = "Tốt lắm!";
      } else if (_reps > 0) {
        feedback = "Bạn đang tập đúng!";
      } else {
        feedback = "";
      }
    }

    return PoseAnalysisResult(
      isPostureCorrect: isPostureCorrect,
      feedbackMessage: feedback,
      shouldCountRep: shouldCountRep,
    );
  }
}
