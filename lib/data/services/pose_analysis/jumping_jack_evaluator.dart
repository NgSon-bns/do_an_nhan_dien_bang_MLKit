import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import 'package:demo/core/utils/pose_math.dart';
import 'base_pose_evaluator.dart';
import 'pose_analysis_result.dart';

class JumpingJackEvaluator extends BasePoseEvaluator {
  String _motionState = 'NEUTRAL';
  final double _landmarkConfidenceThreshold = 0.55;
  bool _isPostureCorrectInCurrentRep = true;
  int _reps = 0;
  int _errorFrames = 0;
  final int _maxAllowedErrorFrames = 4; // Lọc nhiễu khung hình

  @override
  void reset() {
    _motionState = 'NEUTRAL';
    _isPostureCorrectInCurrentRep = true;
    _reps = 0;
    _errorFrames = 0;
  }

  bool _isLandmarkVisible(PoseLandmark? landmark) {
    return landmark != null && landmark.likelihood > _landmarkConfidenceThreshold;
  }

  @override
  PoseAnalysisResult evaluate(Pose pose) {
    bool isPostureCorrect = true;
    String feedback = '';
    bool isBackCorrect = true;
    bool isLegsCorrect = true;
    bool isArmsCorrect = true;
    bool shouldCountRep = false;

    final leftShoulder = pose.landmarks[PoseLandmarkType.leftShoulder];
    final rightShoulder = pose.landmarks[PoseLandmarkType.rightShoulder];
    final leftWrist = pose.landmarks[PoseLandmarkType.leftWrist];
    final rightWrist = pose.landmarks[PoseLandmarkType.rightWrist];
    final leftAnkle = pose.landmarks[PoseLandmarkType.leftAnkle];
    final rightAnkle = pose.landmarks[PoseLandmarkType.rightAnkle];

    if (_isLandmarkVisible(leftShoulder) &&
        _isLandmarkVisible(rightShoulder) &&
        _isLandmarkVisible(leftWrist) &&
        _isLandmarkVisible(rightWrist) &&
        _isLandmarkVisible(leftAnkle) &&
        _isLandmarkVisible(rightAnkle)) {

      double shoulderWidth = PoseMath.calculateDistance(leftShoulder!, rightShoulder!);
      double feetDistance = PoseMath.calculateDistance(leftAnkle!, rightAnkle!);
      double feetRatio = feetDistance / shoulderWidth;

      // ML Kit có gốc tọa độ Y hướng xuống dưới: Cổ tay cao hơn vai thì wrist.y < shoulder.y
      bool leftArmUp = leftWrist!.y < leftShoulder.y;
      bool rightArmUp = rightWrist!.y < rightShoulder.y;
      bool armsAreUp = leftArmUp && rightArmUp;
      
      // Chuẩn hóa khoảng cách tay xuống dưới vai dựa theo chiều rộng vai thay vì 50px cố định
      double armDownThreshold = shoulderWidth * 0.4;
      bool armsAreDown = (leftWrist.y > leftShoulder.y + armDownThreshold) && 
                         (rightWrist.y > rightShoulder.y + armDownThreshold);

      bool feetAreWide = feetRatio > 1.45;    // Tăng độ nhạy (1.55 -> 1.45)
      bool feetAreClosed = feetRatio < 1.15;  // Tăng độ chuẩn xác (1.25 -> 1.15)

      bool isCurrentPostureCorrect = true;

      // Đánh giá tư thế lỗi thời gian thực
      if (feetAreWide && !armsAreUp) {
        isCurrentPostureCorrect = false;
        isArmsCorrect = false;
        feedback = 'Vung tay cao hơn qua đầu!';
      } else if (armsAreUp && !feetAreWide) {
        isCurrentPostureCorrect = false;
        isLegsCorrect = false;
        feedback = 'Nhảy dạng chân rộng ra hơn!';
      }

      // Cập nhật bộ lọc lỗi
      if (!isCurrentPostureCorrect) {
        _errorFrames++;
      } else {
        _errorFrames = 0; // Reset khi tư thế đúng trở lại
      }

      // Áp dụng bộ lọc nhiễu liên tiếp
      if (_errorFrames > _maxAllowedErrorFrames) {
        isPostureCorrect = false;
        if (_motionState == 'ACTIVE' || feetAreWide || armsAreUp) {
          _isPostureCorrectInCurrentRep = false;
        }
      }

      // Thuật toán đếm lần
      if (_motionState == 'NEUTRAL') {
        if (feetAreWide && armsAreUp) {
          _motionState = 'ACTIVE'; // Đạt vị trí đỉnh nhảy
        }
      } else if (_motionState == 'ACTIVE') {
        if (feetAreClosed && armsAreDown) {
          _motionState = 'NEUTRAL'; // Về lại vị trí chuẩn
          if (_isPostureCorrectInCurrentRep) {
            shouldCountRep = true;
            _reps++;
          } else {
            isPostureCorrect = false;
            feedback = 'Lần tập không được tính do sai tư thế!';
          }
          _isPostureCorrectInCurrentRep = true; // Reset cho rep tiếp theo
          _errorFrames = 0; // Reset bộ lọc lỗi khi hoàn thành rep
        }
      }

      // Nếu tập đúng: hiển thị lời khích lệ hoặc số rep
      if (isPostureCorrect) {
        if (shouldCountRep) {
          feedback = "Tốt lắm!";
        } else if (_reps > 0) {
          feedback = "Bạn đang tập đúng!";
        } else {
          feedback = "";
        }
      }
    } else {
      isPostureCorrect = false;
      feedback = 'Đứng lùi xa ra để camera thấy từ đầu đến chân.';
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
