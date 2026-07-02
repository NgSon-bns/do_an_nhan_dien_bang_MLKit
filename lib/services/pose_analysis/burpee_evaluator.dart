import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

import 'base_pose_evaluator.dart';
import 'pose_analysis_result.dart';
import '../../core/utils/pose_math.dart';

enum BurpeeState { stand, squat, plank, recover, jump }

class BurpeeEvaluator extends BasePoseEvaluator {
  BurpeeState _currentState = BurpeeState.stand;
  int _reps = 0;
  final double _landmarkConfidenceThreshold = 0.55;
  double? _standingHipY;
  bool _hasVisitedPlank = false;
  int _plankErrorFrames = 0;

  @override
  void reset() {
    _currentState = BurpeeState.stand;
    _reps = 0;
    _standingHipY = null;
    _hasVisitedPlank = false;
    _plankErrorFrames = 0;
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

    // Tính toán độ tin cậy hiển thị của mỗi bên
    double leftScore = 0;
    if (leftShoulder != null) leftScore += leftShoulder.likelihood;
    if (leftHip != null) leftScore += leftHip.likelihood;
    if (leftKnee != null) leftScore += leftKnee.likelihood;
    if (leftAnkle != null) leftScore += leftAnkle.likelihood;

    double rightScore = 0;
    if (rightShoulder != null) rightScore += rightShoulder.likelihood;
    if (rightHip != null) rightScore += rightHip.likelihood;
    if (rightKnee != null) rightScore += rightKnee.likelihood;
    if (rightAnkle != null) rightScore += rightAnkle.likelihood;

    // Chọn bên hiển thị rõ hơn trước camera
    bool useRight = rightScore >= leftScore;
    final shoulder = useRight ? rightShoulder : leftShoulder;
    final hip = useRight ? rightHip : leftHip;
    final knee = useRight ? rightKnee : leftKnee;
    final ankle = useRight ? rightAnkle : leftAnkle;

    if (shoulder == null ||
        hip == null ||
        knee == null ||
        ankle == null ||
        shoulder.likelihood < _landmarkConfidenceThreshold ||
        hip.likelihood < _landmarkConfidenceThreshold ||
        knee.likelihood < _landmarkConfidenceThreshold ||
        ankle.likelihood < _landmarkConfidenceThreshold) {
      return PoseAnalysisResult(
        isPostureCorrect: false,
        feedbackMessage: "Hãy điều chỉnh tư thế để camera thấy rõ toàn thân.",
        shouldCountRep: false,
      );
    }

    double kneeAngle = PoseMath.getElbowAngle(hip, knee, ankle);
    double hipAngle = PoseMath.getElbowAngle(shoulder, hip, knee);
    double bodyHorizontalAngle = PoseMath.calculateAngleToHorizontal(
      shoulder,
      hip,
    );

    final leftWrist = pose.landmarks[PoseLandmarkType.leftWrist];
    final rightWrist = pose.landmarks[PoseLandmarkType.rightWrist];
    final wrist = useRight ? rightWrist : leftWrist;

    // Kiểm tra xem tay có giơ cao qua đầu/vai không
    bool isHandsRaised = false;
    if (wrist != null && wrist.likelihood >= 0.50) {
      isHandsRaised = wrist.y < shoulder.y;
    }

    bool shouldCountRep = false;
    String feedback = "";
    bool isPostureCorrect = true;

    // 1. Tự động nhận diện và cập nhật chiều cao hông khi đứng thẳng hoàn toàn
    if (kneeAngle > 160 && hipAngle > 160) {
      _standingHipY = hip.y;
    }

    // 2. Chuyển đổi trạng thái phím tắt (Shortcut Transitions) để tránh mất dấu khi tập nhanh
    if (bodyHorizontalAngle < 35 && hipAngle > 135 && kneeAngle > 120) {
      // Đang ở tư thế nằm ngang (Plank) -> Chuyển thẳng sang Plank
      if (_currentState == BurpeeState.stand || _currentState == BurpeeState.squat) {
        _currentState = BurpeeState.plank;
        _hasVisitedPlank = true;
      }
    }

    // 3. Logic chính của máy trạng thái
    switch (_currentState) {
      case BurpeeState.stand:
        if (hipAngle < 115) {
          _currentState = BurpeeState.squat;
          feedback = "Đã ngồi xổm, hãy bật chân ra sau thành Plank!";
        } else {
          feedback = "Hãy ngồi xổm sâu xuống sát mặt sàn.";
        }
        break;

      case BurpeeState.squat:
        if (bodyHorizontalAngle < 35 && hipAngle > 135 && kneeAngle > 120) {
          _currentState = BurpeeState.plank;
          _hasVisitedPlank = true;
          feedback = "Tư thế Plank rất tốt! Hãy nhảy thu chân về.";
        } else if (kneeAngle > 155 && hipAngle > 150 && bodyHorizontalAngle > 70) {
          _currentState = BurpeeState.stand;
          feedback = "Hãy ngồi xổm sâu xuống sát mặt sàn.";
        } else {
          feedback = "Hãy bật cả hai chân ra sau thành tư thế Plank.";
        }
        break;

      case BurpeeState.plank:
        if (hipAngle < 115 && bodyHorizontalAngle > 20) {
          _currentState = BurpeeState.recover;
          feedback = "Đã thu chân về, hãy bật nhảy thẳng người lên!";
        } else if (kneeAngle > 155 && hipAngle > 150 && bodyHorizontalAngle > 70) {
          // Nếu đứng dậy thẳng luôn từ Plank
          if (_hasVisitedPlank && isHandsRaised) {
            _reps++;
            shouldCountRep = true;
            feedback = "Tuyệt vời! Hoàn thành rep $_reps.";
            _currentState = BurpeeState.stand;
            _hasVisitedPlank = false;
          } else {
            _currentState = BurpeeState.stand;
            feedback = "Hãy ngồi xổm sâu xuống sát mặt sàn.";
          }
        } else {
          feedback = "Hãy nhảy thu chân sát về phía hai tay.";
        }
        break;

      case BurpeeState.recover:
        if (kneeAngle > 150 && hipAngle > 140) {
          _currentState = BurpeeState.jump;
          feedback = "Đang bật nhảy...";
        } else {
          feedback = "Hãy đứng thẳng dậy và chuẩn bị bật nhảy.";
        }
        break;

      case BurpeeState.jump:
        double torsoLength = PoseMath.calculateDistance(shoulder, hip);
        bool isJumping = false;
        if (_standingHipY != null) {
          // Chỉ cần nhấc nhẹ hông hoặc giơ tay cao là tính nhảy
          isJumping = hip.y < (_standingHipY! - 0.03 * torsoLength);
        }

        if (((kneeAngle > 155 && hipAngle > 150 && isHandsRaised) || (isJumping && isHandsRaised)) && bodyHorizontalAngle > 65) {
          if (_hasVisitedPlank) {
            _reps++;
            shouldCountRep = true;
            feedback = "Tuyệt vời! Hoàn thành rep $_reps.";
            _currentState = BurpeeState.stand;
            _hasVisitedPlank = false;
          } else {
            _currentState = BurpeeState.stand;
          }
        } else if (kneeAngle < 115 && hipAngle < 115) {
          // Bắt đầu rep mới luôn mà bỏ qua bật nhảy của rep cũ để tránh bị treo
          _currentState = BurpeeState.squat;
          feedback = "Đã ngồi xổm, hãy bật chân ra sau thành Plank!";
        } else {
          feedback = "Nhảy cao lên, duỗi thẳng người và giơ hai tay qua đầu.";
        }
        break;
    }

    // 4. LUẬT PHỤC HỒI TOÀN CỤC (Global Recovery Rule):
    // Nếu đã plank và nay đã đứng dậy giơ tay -> Chắc chắn hoàn thành 1 Burpee bất chấp lỗi trôi frame
    if (_hasVisitedPlank && kneeAngle > 155 && hipAngle > 150 && isHandsRaised && bodyHorizontalAngle > 65) {
      _reps++;
      shouldCountRep = true;
      feedback = "Tuyệt vời! Hoàn thành rep $_reps.";
      _currentState = BurpeeState.stand;
      _hasVisitedPlank = false;
    }

    // Kiểm tra lỗi tư thế khi Plank (chỉ khi đang ở trạng thái Plank và bị lỗi kéo dài để lọc nhiễu lúc nhảy chân xuống)
    if (_currentState == BurpeeState.plank && kneeAngle > 140 && hipAngle > 140) {
      if (bodyHorizontalAngle >= 25 && bodyHorizontalAngle < 65) {
        _plankErrorFrames++;
        if (_plankErrorFrames > 8) { // Cần bị lỗi liên tiếp > 8 frame (~0.3s) mới báo đỏ
          isPostureCorrect = false;
          feedback = "Hãy giữ lưng và hông thẳng song song mặt sàn (Plank)!";
        }
      } else {
        _plankErrorFrames = 0;
      }
    } else {
      _plankErrorFrames = 0;
    }

    // Nếu tập đúng
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
