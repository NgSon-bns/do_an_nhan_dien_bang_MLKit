import 'dart:math' as math;
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import 'package:demo/core/utils/pose_math.dart';
import 'base_pose_evaluator.dart';
import 'pose_analysis_result.dart';

class PlankEvaluator extends BasePoseEvaluator {
  final double _landmarkConfidenceThreshold = 0.45;

  int _errorFrames = 0;
  final int _maxAllowedErrorFrames = 10;

  @override
  void reset() {
    _errorFrames = 0;
  }

  bool _isLandmarkVisible(PoseLandmark? landmark) {
    return landmark != null &&
        landmark.likelihood > _landmarkConfidenceThreshold;
  }

  bool _isSideVisible(Pose pose, bool isRight) {
    final shoulder =
        pose.landmarks[isRight
            ? PoseLandmarkType.rightShoulder
            : PoseLandmarkType.leftShoulder];
    final hip =
        pose.landmarks[isRight
            ? PoseLandmarkType.rightHip
            : PoseLandmarkType.leftHip];
    final knee =
        pose.landmarks[isRight
            ? PoseLandmarkType.rightKnee
            : PoseLandmarkType.leftKnee];
    final ankle =
        pose.landmarks[isRight
            ? PoseLandmarkType.rightAnkle
            : PoseLandmarkType.leftAnkle];

    return _isLandmarkVisible(shoulder) &&
        _isLandmarkVisible(hip) &&
        (_isLandmarkVisible(knee) || _isLandmarkVisible(ankle));
  }

  bool _isInPlankPosition(PoseLandmark shoulder, PoseLandmark legJoint) {
    final double dx = (shoulder.x - legJoint.x).abs();
    final double dy = (shoulder.y - legJoint.y).abs();

    if (dx < 0.15) return false;

    final double bodyInclineAngle = math.atan2(dy, dx) * (180 / math.pi);

    const double maxPlankInclineAngle = 40.0;

    return bodyInclineAngle <= maxPlankInclineAngle;
  }

  @override
  PoseAnalysisResult evaluate(Pose pose) {
    bool isPostureCorrect = true;
    String feedback = '';
    bool isBackCorrect = true;
    bool isLegsCorrect = true;
    bool isArmsCorrect = true;
    String feedbackErr = '';

    bool rightSideVisible = _isSideVisible(pose, true);
    bool leftSideVisible = _isSideVisible(pose, false);

    if (rightSideVisible || leftSideVisible) {
      final bool useRightSide =
          rightSideVisible &&
          (!leftSideVisible ||
              (pose.landmarks[PoseLandmarkType.rightShoulder]!.likelihood >
                  pose.landmarks[PoseLandmarkType.leftShoulder]!.likelihood));

      final shoulder = useRightSide
          ? pose.landmarks[PoseLandmarkType.rightShoulder]!
          : pose.landmarks[PoseLandmarkType.leftShoulder]!;
      final hip = useRightSide
          ? pose.landmarks[PoseLandmarkType.rightHip]!
          : pose.landmarks[PoseLandmarkType.leftHip]!;
      final knee = useRightSide
          ? pose.landmarks[PoseLandmarkType.rightKnee]
          : pose.landmarks[PoseLandmarkType.leftKnee];
      final ankle = useRightSide
          ? pose.landmarks[PoseLandmarkType.rightAnkle]
          : pose.landmarks[PoseLandmarkType.leftAnkle];

      final bool hasAnkle = _isLandmarkVisible(ankle);
      final legJoint = hasAnkle ? ankle! : knee!;

      if (!_isInPlankPosition(shoulder, legJoint)) {
        _errorFrames = 0;
        return PoseAnalysisResult(
          isPostureCorrect: false,
          feedbackMessage: 'Hãy nằm ngang xuống để bắt đầu tập Plank!',
          isBackCorrect: false,
          isLegsCorrect: false,
          isArmsCorrect: false,
          shouldCountRep: false,
        );
      }

      double bodyLineAngle = (shoulder.x < hip.x)
          ? PoseMath.getElbowAngle(shoulder, hip, legJoint)
          : PoseMath.getElbowAngle(legJoint, hip, shoulder);

      bool isCurrentPostureCorrect = true;

      if (legJoint.x != shoulder.x) {
        double expectedHipY =
            shoulder.y +
            (legJoint.y - shoulder.y) *
                (hip.x - shoulder.x) /
                (legJoint.x - shoulder.x);

        if (bodyLineAngle < 160) {
          isCurrentPostureCorrect = false;
          isBackCorrect = false;

          if (hip.y < expectedHipY - 0.04) {
            feedbackErr = 'Hông quá cao, hãy hạ thấp hông xuống!';
          } else if (hip.y > expectedHipY + 0.04) {
            feedbackErr = 'Thân người bị võng, hãy siết cơ bụng nâng hông lên!';
          } else {
            feedbackErr = 'Hãy giữ vai, hông và chân thẳng hàng!';
          }
        }
        print('$bodyLineAngle, $hip.y, $expectedHipY');
      }
      print(bodyLineAngle);
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
      feedback = 'Hãy điều chỉnh tư thế nằm ngang để camera nhìn rõ bên sườn.';
    }

    if (isPostureCorrect) {
      feedback = "Bạn đang tập đúng!";
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
