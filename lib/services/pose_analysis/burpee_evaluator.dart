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

  @override
  void reset() {
    _currentState = BurpeeState.stand;
    _reps = 0;
    _standingHipY = null;
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
    String feedback = "Đang thực hiện...";
    bool isPostureCorrect = true;

    switch (_currentState) {
      case BurpeeState.stand:
        // Đứng thẳng: tự động cập nhật chiều cao hông khi người tập đứng thẳng hoàn toàn
        if (kneeAngle > 160 && hipAngle > 160) {
          _standingHipY = hip.y;
        }
        // Chuyển sang squat khi gối và hông gập sâu sát đất (góc < 100 độ)
        if (kneeAngle < 100 && hipAngle < 100) {
          _currentState = BurpeeState.squat;
          feedback = "Đã ngồi xổm, hãy bật chân ra sau thành Plank!";
        } else {
          feedback = "Hãy ngồi xổm sâu xuống sát mặt sàn (góc gối < 100°).";
        }
        break;

      case BurpeeState.squat:
        // Đã ngồi xổm, bật chân ra sau làm Plank thẳng người nằm ngang (gối/hông duỗi thẳng > 160 độ, thân nghiêng < 25 độ)
        if (kneeAngle > 160 && hipAngle > 160 && bodyHorizontalAngle < 25) {
          _currentState = BurpeeState.plank;
          feedback = "Tư thế Plank thẳng người rất tốt! Hãy nhảy thu chân về.";
        } else if (kneeAngle > 155 &&
            hipAngle > 150 &&
            bodyHorizontalAngle > 70) {
          // Trở lại đứng thẳng (người tập đứng dậy thẳng lưng mà không bật chân làm plank)
          _currentState = BurpeeState.stand;
          feedback = "Hãy ngồi xổm sâu xuống sát mặt sàn.";
        } else {
          feedback =
              "Hãy bật cả hai chân ra sau, giữ thân thẳng song song mặt sàn (Plank).";
        }
        break;

      case BurpeeState.plank:
        // Ở thế Plank, chuẩn bị thu chân về tư thế squat gập sâu
        if (kneeAngle < 105 && hipAngle < 105 && bodyHorizontalAngle > 50) {
          _currentState = BurpeeState.recover;
          feedback = "Đã thu chân về, hãy bật nhảy thẳng người lên!";
        } else if (kneeAngle > 155 &&
            hipAngle > 150 &&
            bodyHorizontalAngle > 70) {
          // Đứng dậy trực tiếp từ Plank (hủy rep)
          _currentState = BurpeeState.stand;
          feedback = "Hãy ngồi xổm sâu xuống sát mặt sàn.";
        } else {
          feedback = "Hãy nhảy thu chân sát về phía hai tay (góc gối < 105°).";
        }
        break;

      case BurpeeState.recover:
        // Thu chân về squat, chuẩn bị bật nhảy lên cao
        if (kneeAngle > 155 && hipAngle > 145) {
          _currentState = BurpeeState.jump;
          feedback = "Đang bật nhảy...";
        } else {
          feedback = "Hãy đứng thẳng dậy và chuẩn bị bật nhảy.";
        }
        break;

      case BurpeeState.jump:
        // Thực hiện nhảy thẳng người, hai tay giơ qua đầu và thân người bật nhấc cao khỏi sàn
        double torsoLength = PoseMath.calculateDistance(shoulder, hip);
        bool isJumping = false;
        if (_standingHipY != null) {
          // Trọng tâm cơ thể (hông) nhấc cao lên so với lúc đứng thẳng ít nhất 8% chiều dài thân (feet rời đất)
          isJumping = hip.y < (_standingHipY! - 0.08 * torsoLength);
        } else {
          isJumping = false; // Chưa xác định được chiều cao khi đứng thẳng;
        }

        if (kneeAngle > 165 && hipAngle > 160 && isHandsRaised && isJumping) {
          _reps++;
          shouldCountRep = true;
          feedback = "Tuyệt vời! Hoàn thành rep $_reps.";
          _currentState = BurpeeState.stand;
        } else if (kneeAngle < 115 && hipAngle < 115) {
          // Bắt đầu rep mới luôn mà bỏ qua bật nhảy của rep cũ để tránh bị treo ở bước nhảy
          _currentState = BurpeeState.squat;
          feedback = "Đã ngồi xổm, hãy bật chân ra sau thành Plank!";
        } else {
          feedback = "Nhảy cao lên, duỗi thẳng người và giơ hai tay qua đầu.";
        }
        break;
    }

    // Kiểm tra lỗi tư thế khi Plank (nếu chân thẳng nhưng người không nằm ngang)
    if ((_currentState == BurpeeState.squat || _currentState == BurpeeState.plank) &&
        kneeAngle > 140 && hipAngle > 140) {
      if (bodyHorizontalAngle >= 25 && bodyHorizontalAngle < 65) {
        isPostureCorrect = false;
        feedback = "Hãy giữ lưng và hông thẳng song song mặt sàn (Plank)!";
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
      shouldCountRep: shouldCountRep,
    );
  }
}
