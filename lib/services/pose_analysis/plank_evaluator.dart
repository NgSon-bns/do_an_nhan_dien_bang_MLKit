import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import '../../core/utils/pose_math.dart';
import 'base_pose_evaluator.dart';
import 'pose_analysis_result.dart';

class PlankEvaluator extends BasePoseEvaluator {
  final double _landmarkConfidenceThreshold = 0.45; // Giảm xuống 0.45 để nhạy hơn với môi trường thiếu sáng/nhiễu

  // Bộ lọc nhiễu
  int _errorFrames = 0;
  final int _maxAllowedErrorFrames = 10; // Giảm bớt số khung trễ để phản hồi nhanh hơn

  @override
  void reset() {
    _errorFrames = 0;
  }

  bool _isLandmarkVisible(PoseLandmark? landmark) {
    return landmark != null &&
        landmark.likelihood > _landmarkConfidenceThreshold;
  }

  bool _isSideVisible(Pose pose, bool isRight) {
    final shoulder = pose.landmarks[isRight ? PoseLandmarkType.rightShoulder : PoseLandmarkType.leftShoulder];
    final hip = pose.landmarks[isRight ? PoseLandmarkType.rightHip : PoseLandmarkType.leftHip];
    final knee = pose.landmarks[isRight ? PoseLandmarkType.rightKnee : PoseLandmarkType.leftKnee];
    final ankle = pose.landmarks[isRight ? PoseLandmarkType.rightAnkle : PoseLandmarkType.leftAnkle];

    // Cần nhìn thấy Vai, Hông và ít nhất một trong hai khớp Chân (Gối hoặc Cổ chân)
    return _isLandmarkVisible(shoulder) &&
        _isLandmarkVisible(hip) &&
        (_isLandmarkVisible(knee) || _isLandmarkVisible(ankle));
  }

  @override
  PoseAnalysisResult evaluate(Pose pose) {
    bool isPostureCorrect = true;
    String feedback = '';
    bool isBackCorrect = true;
    bool isLegsCorrect = true;
    bool isArmsCorrect = true;
    String feedbackErr = '';

    // Kiểm tra xem khớp bên sườn nào hiển thị rõ ràng hơn
    bool rightSideVisible = _isSideVisible(pose, true);
    bool leftSideVisible = _isSideVisible(pose, false);

    if (rightSideVisible || leftSideVisible) {
      // Chọn bên có độ tin cậy của Vai cao hơn
      final bool useRightSide = rightSideVisible && (!leftSideVisible || 
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

      // Xác định điểm mốc chân phù hợp (Ưu tiên cổ chân, nếu khuất thì dùng đầu gối)
      final bool hasAnkle = _isLandmarkVisible(ankle);
      final legJoint = hasAnkle ? ankle! : knee!;

      // 3. Tính toán góc thẳng hàng thân người (Shoulder - Hip - LegJoint)
      double bodyLineAngle = (shoulder.x < hip.x)
          ? PoseMath.calculateAngle(shoulder, hip, legJoint)
          : PoseMath.calculateAngle(legJoint, hip, shoulder);

      // 4. Kiểm tra tư thế (Cập nhật bộ lọc lỗi)
      bool isCurrentPostureCorrect = true;
      
      // Kiểm tra độ thẳng hàng của Lưng và Hông (Áp dụng cho mọi góc nhìn sườn, xéo)
      if (legJoint.x != shoulder.x) {
        // Tính toán tọa độ Y dự kiến của hông nằm trên đường thẳng nối vai-chân
        double expectedHipY = shoulder.y + (legJoint.y - shoulder.y) * (hip.x - shoulder.x) / (legJoint.x - shoulder.x);
        
        // Plank chuẩn góc gấp khúc thân người phải rộng (>= 165 độ)
        if (bodyLineAngle < 165) {
          isCurrentPostureCorrect = false;
          isBackCorrect = false;
          // Tọa độ màn hình Flutter tăng dần đi xuống dưới (Y bé hơn là cao hơn)
          if (hip.y < expectedHipY - 0.04) {
            feedbackErr = 'Hông quá cao, hãy hạ thấp hông xuống!';
          } else if (hip.y > expectedHipY + 0.04) {
            feedbackErr = 'Thân người bị võng, hãy siết cơ bụng nâng hông lên!';
          } else {
            feedbackErr = 'Hãy giữ vai, hông và chân thẳng hàng!';
          }
        }
      }

      // Logic bộ lọc nhiễu
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

    // Nếu tập đúng: hiển thị câu khích lệ mặc định
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
