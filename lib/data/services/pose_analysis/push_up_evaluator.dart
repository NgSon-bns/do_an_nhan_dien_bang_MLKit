import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import 'package:demo/core/utils/pose_math.dart';
import 'base_pose_evaluator.dart';
import 'pose_analysis_result.dart';

class PushUpEvaluator extends BasePoseEvaluator {
  String _motionState = 'UP';
  final double _landmarkConfidenceThreshold = 0.55;
  bool _isPostureCorrectInCurrentRep = true;
  bool _isPushUpDeepEnoughInCurrentRep = false; // Theo dõi độ sâu đạt được trong rep hiện tại
  bool _isRightSideVisible = true;
  int _reps = 0;

  double _standingShoulderY = 0; // Mốc để so sánh độ sâu
  int _errorFrames = 0; // Bộ lọc nhiễu khung hình
  bool isBackCorrect = true;

  @override
  void reset() {
    _motionState = 'UP';
    _isPostureCorrectInCurrentRep = true;
    _isPushUpDeepEnoughInCurrentRep = false;
    _standingShoulderY = 0;
    _errorFrames = 0;
    isBackCorrect = true;
    _reps = 0;
  }

  bool _isLandmarkVisible(PoseLandmark? landmark) {
    return landmark != null &&
        landmark.likelihood > _landmarkConfidenceThreshold;
  }

  @override
  PoseAnalysisResult evaluate(Pose pose) {
    bool isPostureCorrect = true;
    String feedback = '';
    bool shouldCountRep = false;

    // Lấy landmark
    final leftShoulder = pose.landmarks[PoseLandmarkType.leftShoulder];
    final leftElbow = pose.landmarks[PoseLandmarkType.leftElbow];
    final leftWrist = pose.landmarks[PoseLandmarkType.leftWrist];
    final rightShoulder = pose.landmarks[PoseLandmarkType.rightShoulder];
    final rightElbow = pose.landmarks[PoseLandmarkType.rightElbow];
    final rightWrist = pose.landmarks[PoseLandmarkType.rightWrist];
    final rightHip = pose.landmarks[PoseLandmarkType.rightHip];
    final leftHip = pose.landmarks[PoseLandmarkType.leftHip];
    final rightKnee = pose.landmarks[PoseLandmarkType.rightKnee];
    final leftKnee = pose.landmarks[PoseLandmarkType.leftKnee];

    if (!_isLandmarkVisible(rightShoulder) ||
        !_isLandmarkVisible(rightHip) ||
        !_isLandmarkVisible(rightWrist)) {
      return PoseAnalysisResult(
        isPostureCorrect: false,
        feedbackMessage: 'Cần nhìn thấy vai, hông và cổ tay của bạn',
      );
    }

    // 1. Xác định góc khuỷu tay
    double? elbowAngle;
    if ((rightShoulder!.x < rightHip!.x) &&
        _isLandmarkVisible(rightShoulder) &&
        _isLandmarkVisible(rightElbow) &&
        _isLandmarkVisible(rightWrist)) {
      elbowAngle = PoseMath.getElbowAngle(
        rightShoulder!,
        rightElbow!,
        rightWrist!,
      );
      _isRightSideVisible = true;
    } else if ((leftShoulder!.x > leftHip!.x) &&
        _isLandmarkVisible(leftShoulder) &&
        _isLandmarkVisible(leftElbow) &&
        _isLandmarkVisible(leftWrist)) {
      elbowAngle = PoseMath.getElbowAngle(
        leftShoulder!,
        leftElbow!,
        leftWrist!,
      );
      _isRightSideVisible = false;
    }

    if (elbowAngle == null)
      return PoseAnalysisResult(
        isPostureCorrect: false,
        feedbackMessage: 'Hãy nghiêng người để camera thấy rõ khuỷu tay',
      );

    final currentShoulder = _isRightSideVisible ? rightShoulder! : leftShoulder!;
    final currentHip = _isRightSideVisible ? rightHip! : leftHip!;

    // 2. Calibrate mốc (khi tay thẳng hoặc chưa có mốc khởi tạo)
    if (elbowAngle > 160 || _standingShoulderY == 0) {
      _standingShoulderY = currentShoulder.y;
    }

    // Tính độ dài thân người (khoảng cách giữa vai và hông) để làm mốc tỷ lệ cơ thể
    double torsoLength = PoseMath.calculateDistance(currentShoulder, currentHip);
    if (torsoLength < 1) torsoLength = 1; // Tránh lỗi chia cho 0

    // Kiểm tra độ dịch chuyển đi xuống chuẩn hóa theo tỷ lệ cơ thể
    if (_standingShoulderY > 0) {
      double verticalDisplacement = currentShoulder.y - _standingShoulderY;
      double normalizedDisplacement = verticalDisplacement / torsoLength;

      // Nếu độ sâu hạ người đạt tối thiểu 10% chiều dài thân người, ghi nhận đạt độ sâu của rep này
      if (normalizedDisplacement >= 0.10) {
        _isPushUpDeepEnoughInCurrentRep = true;
      }
    }

    // 3. Phân tích tư thế lưng (Shoulder - Hip - Knee)
    double backAngle = (rightShoulder!.x > rightHip!.x)
        ? PoseMath.calculateAngle(
            (_isRightSideVisible ? rightShoulder! : leftShoulder!),
            (_isRightSideVisible ? rightHip! : leftHip!),
            (_isRightSideVisible ? rightKnee! : leftKnee!),
          )
        : PoseMath.calculateAngle(
            (_isRightSideVisible ? rightKnee! : leftKnee!),
            (_isRightSideVisible ? rightHip! : leftHip!),
            (_isRightSideVisible ? rightShoulder! : leftShoulder!),
          );

    // Tăng nhẹ dung sai góc thẳng hàng để tránh báo lỗi nhạy cảm do nhiễu camera (từ 160->152, 195->200)
    bool isBackAligned = (backAngle >= 152 && backAngle <= 200);

    // 4. Lọc nhiễu tư thế
    if (!isBackAligned) {
      _errorFrames++;
      if (_errorFrames > 8) { // Cần sai tư thế liên tục > 8 frame (~0.3s) mới báo lỗi đỏ
        isPostureCorrect = false;
        feedback = 'Giữ vai hông và chân thẳng hàng!';
        _isPostureCorrectInCurrentRep = false;
        isBackCorrect = false;
      }
    } else {
      _errorFrames = 0;
      isBackCorrect = true;
    }

    if (elbowAngle < 110) {
      if (_motionState == 'UP') {
        _motionState = 'DOWN';
        _isPostureCorrectInCurrentRep = true;
        _isPushUpDeepEnoughInCurrentRep = false; // Reset độ sâu cho rep tập mới
        print(
          'down Elbow Angle: $elbowAngle, Back Angle: $backAngle, Shoulder Y: ${currentShoulder.y}, Standing Shoulder Y: $_standingShoulderY, Error Frames: $_errorFrames, Is Posture Correct: $_isPostureCorrectInCurrentRep, Is PushUp Deep Enough: $_isPushUpDeepEnoughInCurrentRep,shouldCountRep: $shouldCountRep',
        ); // Reset trạng thái khi bắt đầu xuống
      }
    } else if (elbowAngle > 150) {
      if (_motionState == 'DOWN') {
        _motionState = 'UP';
        if (_isPostureCorrectInCurrentRep && _isPushUpDeepEnoughInCurrentRep) {
          shouldCountRep = true;
          _reps++;
          feedback = 'Tuyệt vời!';
        } else {
          isPostureCorrect = false;
          if (!_isPushUpDeepEnoughInCurrentRep) {
            feedback = 'Hãy xuống sâu hơn nữa!';
          } else {
            feedback = 'Lần tập không được tính do sai tư thế!';
          }
        }
        print(
          'up Elbow Angle: $elbowAngle, Back Angle: $backAngle, Shoulder Y: ${currentShoulder.y}, Standing Shoulder Y: $_standingShoulderY, Error Frames: $_errorFrames, Is Posture Correct: $_isPostureCorrectInCurrentRep, Is PushUp Deep Enough: $_isPushUpDeepEnoughInCurrentRep,shouldCountRep: $shouldCountRep',
        );
      }
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
      isBackCorrect: true,
      isLegsCorrect: true,
      isArmsCorrect: true,
      shouldCountRep: shouldCountRep,
    );
  }
}
