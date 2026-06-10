import 'package:flutter/material.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

class PoseSkeletonPainter extends CustomPainter {
  final Pose pose;
  final Size imageSize;
  final InputImageRotation rotation;
  final bool isFrontCamera;
  
  // Trạng thái tư thế của các bộ phận để tô màu phản hồi (Xanh/Đỏ)
  final bool isBackCorrect;
  final bool isLegsCorrect;
  final bool isArmsCorrect;

  PoseSkeletonPainter({
    required this.pose,
    required this.imageSize,
    required this.rotation,
    required this.isFrontCamera,
    this.isBackCorrect = true,
    this.isLegsCorrect = true,
    this.isArmsCorrect = true,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paintJoint = Paint()
      ..color = Colors.white
      ..strokeWidth = 4.0
      ..style = PaintingStyle.fill;

    // Định nghĩa các loại bút vẽ xương
    final paintCorrectBone = Paint()
      ..color = Colors.greenAccent.withValues(alpha: 0.85)
      ..strokeWidth = 5.0
      ..strokeCap = StrokeCap.round;

    final paintIncorrectBone = Paint()
      ..color = Colors.redAccent.withValues(alpha: 0.95)
      ..strokeWidth = 6.0
      ..strokeCap = StrokeCap.round;

    // Hiệu ứng phát sáng cho xương sai tư thế
    final paintGlow = Paint()
      ..color = Colors.red.withValues(alpha: 0.4)
      ..strokeWidth = 12.0
      ..strokeCap = StrokeCap.round
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5.0);

    // Chuyển đổi tọa độ từ ảnh camera sang canvas màn hình
    double translateX(double x) {
      double translated;
      // Dựa trên góc xoay của cảm biến camera để tính tỷ lệ chiếu
      if (rotation == InputImageRotation.rotation90deg ||
          rotation == InputImageRotation.rotation270deg) {
        translated = x * size.width / imageSize.height;
      } else {
        translated = x * size.width / imageSize.width;
      }

      // Nếu dùng camera trước, ta cần lật ngược ảnh theo phương ngang (mirror)
      return isFrontCamera ? size.width - translated : translated;
    }

    double translateY(double y) {
      if (rotation == InputImageRotation.rotation90deg ||
          rotation == InputImageRotation.rotation270deg) {
        return y * size.height / imageSize.width;
      } else {
        return y * size.height / imageSize.height;
      }
    }

    Offset getOffset(PoseLandmarkType type) {
      final landmark = pose.landmarks[type];
      if (landmark == null) return Offset.zero;
      return Offset(translateX(landmark.x), translateY(landmark.y));
    }

    bool hasLandmarks(List<PoseLandmarkType> types) {
      return types.every((t) => pose.landmarks[t] != null);
    }

    // Vẽ một đoạn xương (nối 2 khớp)
    void drawBone(PoseLandmarkType startType, PoseLandmarkType endType, Paint paint, {Paint? glowPaint}) {
      if (!hasLandmarks([startType, endType])) return;
      final start = getOffset(startType);
      final end = getOffset(endType);
      if (start == Offset.zero || end == Offset.zero) return;

      if (glowPaint != null) {
        canvas.drawLine(start, end, glowPaint);
      }
      canvas.drawLine(start, end, paint);
    }

    // 1. Phân loại và vẽ các đoạn xương khớp
    
    // Bút vẽ nhóm Tay
    final armPaint = isArmsCorrect ? paintCorrectBone : paintIncorrectBone;
    final armGlow = isArmsCorrect ? null : paintGlow;

    // Vẽ tay trái
    drawBone(PoseLandmarkType.leftShoulder, PoseLandmarkType.leftElbow, armPaint, glowPaint: armGlow);
    drawBone(PoseLandmarkType.leftElbow, PoseLandmarkType.leftWrist, armPaint, glowPaint: armGlow);
    // Vẽ tay phải
    drawBone(PoseLandmarkType.rightShoulder, PoseLandmarkType.rightElbow, armPaint, glowPaint: armGlow);
    drawBone(PoseLandmarkType.rightElbow, PoseLandmarkType.rightWrist, armPaint, glowPaint: armGlow);

    // Bút vẽ nhóm Thân người / Lưng
    final backPaint = isBackCorrect ? paintCorrectBone : paintIncorrectBone;
    final backGlow = isBackCorrect ? null : paintGlow;

    // Vẽ thân/lưng (Vai -> Hông)
    drawBone(PoseLandmarkType.leftShoulder, PoseLandmarkType.leftHip, backPaint, glowPaint: backGlow);
    drawBone(PoseLandmarkType.rightShoulder, PoseLandmarkType.rightHip, backPaint, glowPaint: backGlow);
    drawBone(PoseLandmarkType.leftShoulder, PoseLandmarkType.rightShoulder, backPaint, glowPaint: backGlow);
    drawBone(PoseLandmarkType.leftHip, PoseLandmarkType.rightHip, backPaint, glowPaint: backGlow);

    // Bút vẽ nhóm Chân
    final legPaint = isLegsCorrect ? paintCorrectBone : paintIncorrectBone;
    final legGlow = isLegsCorrect ? null : paintGlow;

    // Vẽ chân trái
    drawBone(PoseLandmarkType.leftHip, PoseLandmarkType.leftKnee, legPaint, glowPaint: legGlow);
    drawBone(PoseLandmarkType.leftKnee, PoseLandmarkType.leftAnkle, legPaint, glowPaint: legGlow);
    // Vẽ chân phải
    drawBone(PoseLandmarkType.rightHip, PoseLandmarkType.rightKnee, legPaint, glowPaint: legGlow);
    drawBone(PoseLandmarkType.rightKnee, PoseLandmarkType.rightAnkle, legPaint, glowPaint: legGlow);

    // 2. Vẽ các điểm khớp tròn (Joints) để khung xương sinh động hơn
    for (final landmark in pose.landmarks.values) {
      if (landmark.type == PoseLandmarkType.leftEye ||
          landmark.type == PoseLandmarkType.rightEye ||
          landmark.type == PoseLandmarkType.leftEar ||
          landmark.type == PoseLandmarkType.rightEar ||
          landmark.type == PoseLandmarkType.nose) {
        // Bỏ qua vẽ các khớp trên mặt để tránh che tầm nhìn
        continue;
      }
      final offset = Offset(translateX(landmark.x), translateY(landmark.y));
      if (offset != Offset.zero) {
        canvas.drawCircle(offset, 4.0, paintJoint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant PoseSkeletonPainter oldDelegate) {
    return oldDelegate.pose != pose ||
        oldDelegate.isBackCorrect != isBackCorrect ||
        oldDelegate.isLegsCorrect != isLegsCorrect ||
        oldDelegate.isArmsCorrect != isArmsCorrect ||
        oldDelegate.isFrontCamera != isFrontCamera;
  }
}
