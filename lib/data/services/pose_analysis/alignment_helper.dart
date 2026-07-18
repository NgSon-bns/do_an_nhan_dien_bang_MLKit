import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import 'package:demo/domain/exercise.dart';

enum CameraAngle {
  front,          // Thẳng đối diện mặt
  diagonalLeft,   // Xéo bên trái 45 độ
  diagonalRight,  // Xéo bên phải 45 độ
  side,           // Góc ngang thân
}

class AlignmentResult {
  final bool isAligned;
  final CameraAngle currentAngle;
  final double currentYaw;
  final String feedbackMessage;
  final bool isBodyInFrame;
  final bool isAngleCorrect;

  AlignmentResult({
    required this.isAligned,
    required this.currentAngle,
    required this.currentYaw,
    required this.feedbackMessage,
    required this.isBodyInFrame,
    required this.isAngleCorrect,
  });
}

class AlignmentHelper {
  /// Ước lượng góc xoay quanh trục thẳng đứng (Yaw) của cơ thể
  /// Kết quả tính bằng độ (°), trong khoảng [-90, 90]
  /// Góc dương: quay người sang trái (vai trái lùi xa, vai phải tiến gần)
  /// Góc âm: quay người sang phải (vai phải lùi xa, vai trái tiến gần)
  static double estimateBodyYaw(Pose pose) {
    final leftShoulder = pose.landmarks[PoseLandmarkType.leftShoulder];
    final rightShoulder = pose.landmarks[PoseLandmarkType.rightShoulder];
    final leftHip = pose.landmarks[PoseLandmarkType.leftHip];
    final rightHip = pose.landmarks[PoseLandmarkType.rightHip];

    double shoulderYaw = 0;
    int count = 0;

    if (leftShoulder != null && rightShoulder != null) {
      final dx = (leftShoulder.x - rightShoulder.x).abs();
      final dz = leftShoulder.z - rightShoulder.z;
      if (dx > 5) { // tránh chia cho số quá nhỏ
        shoulderYaw = math.atan2(dz, dx) * 180 / math.pi;
        count++;
      }
    }

    double hipYaw = 0;
    if (leftHip != null && rightHip != null) {
      final dx = (leftHip.x - rightHip.x).abs();
      final dz = leftHip.z - rightHip.z;
      if (dx > 5) {
        hipYaw = math.atan2(dz, dx) * 180 / math.pi;
        count++;
      }
    }

    if (count == 0) return 0;
    return (shoulderYaw + hipYaw) / count;
  }

  /// Phân loại góc camera hiện tại dựa trên góc Yaw của thân người
  static CameraAngle getCameraAngle(double yaw) {
    if (yaw.abs() <= 25.0) {
      return CameraAngle.front;
    } else if (yaw > 25.0 && yaw < 65.0) {
      return CameraAngle.diagonalLeft;
    } else if (yaw < -25.0 && yaw > -65.0) {
      return CameraAngle.diagonalRight;
    } else {
      return CameraAngle.side;
    }
  }

  /// Trả về mô tả tiếng Việt cho góc camera
  static String getAngleName(CameraAngle angle) {
    switch (angle) {
      case CameraAngle.front:
        return 'Thẳng đối diện';
      case CameraAngle.diagonalLeft:
        return 'Xéo bên trái (45°)';
      case CameraAngle.diagonalRight:
        return 'Xéo bên phải (45°)';
      case CameraAngle.side:
        return 'Góc ngang thân';
    }
  }

  /// Xác định xem bài tập này dùng khung đứng hay khung ngang
  static bool isHorizontalLayout(ExerciseType exerciseType) {
    // Plank và Push-Up là các bài nằm ngang trên sàn nhà
    if (exerciseType == ExerciseType.plank || exerciseType == ExerciseType.pushUp) {
      return true;
    }
    return false;
  }

  /// Chuyển đổi tọa độ từ ảnh camera sang canvas màn hình (đồng bộ với PoseSkeletonPainter)
  static Offset translateCoordinates({
    required double x,
    required double y,
    required Size imageSize,
    required Size screenSize,
    required InputImageRotation rotation,
    required bool isFrontCamera,
  }) {
    double translatedX;
    double translatedY;

    if (rotation == InputImageRotation.rotation90deg ||
        rotation == InputImageRotation.rotation270deg) {
      translatedX = x * screenSize.width / imageSize.height;
      translatedY = y * screenSize.height / imageSize.width;
    } else {
      translatedX = x * screenSize.width / imageSize.width;
      translatedY = y * screenSize.height / imageSize.height;
    }

    if (isFrontCamera) {
      translatedX = screenSize.width - translatedX;
    }

    return Offset(translatedX, translatedY);
  }

  /// Kiểm tra xem người dùng đã đứng đúng khung hình hay chưa (Dung sai cao)
  static AlignmentResult checkAlignment({
    required Pose pose,
    required ExerciseType exerciseType,
    required Size screenSize,
    required Size imageSize,
    required InputImageRotation rotation,
    required bool isFrontCamera,
  }) {
    final yaw = estimateBodyYaw(pose);
    final currentAngle = getCameraAngle(yaw);

    // 1. Tính toán khung chữ nhật chỉ định trên màn hình
    final isHorizontal = isHorizontalLayout(exerciseType);
    final double boxWidth;
    final double boxHeight;
    final double boxLeft;
    final double boxTop;

    if (isHorizontal) {
      // Khung ngang cho Plank/Pushup
      boxWidth = screenSize.width * 0.90;
      boxHeight = screenSize.height * 0.45;
      boxLeft = (screenSize.width - boxWidth) / 2;
      boxTop = (screenSize.height - boxHeight) / 2 + 60; // Dịch xuống dưới sàn một chút
    } else {
      // Khung đứng cho Squat/Jumping Jack/Lunge/Burpee
      boxWidth = screenSize.width * 0.65;
      boxHeight = screenSize.height * 0.80;
      boxLeft = (screenSize.width - boxWidth) / 2;
      boxTop = (screenSize.height - boxHeight) / 2;
    }

    final frameRect = Rect.fromLTWH(boxLeft, boxTop, boxWidth, boxHeight);

    // Áp dụng dung sai 15% nới lỏng viền kiểm tra (mở rộng vùng hợp lệ)
    final toleranceX = boxWidth * 0.15;
    final toleranceY = boxHeight * 0.15;
    final checkRect = Rect.fromLTRB(
      frameRect.left - toleranceX,
      frameRect.top - toleranceY,
      frameRect.right + toleranceX,
      frameRect.bottom + toleranceY,
    );

    // 2. Kiểm tra xem các khớp có nằm trong khung hay không
    bool isBodyInFrame = false;
    const double minLikelihood = 0.45; // Ngưỡng tin cậy thấp để dễ nhận diện

    Offset getScreenOffset(PoseLandmarkType type) {
      final lm = pose.landmarks[type];
      if (lm == null) return Offset.zero;
      return translateCoordinates(
        x: lm.x,
        y: lm.y,
        imageSize: imageSize,
        screenSize: screenSize,
        rotation: rotation,
        isFrontCamera: isFrontCamera,
      );
    }

    bool isVisible(PoseLandmarkType type) {
      final lm = pose.landmarks[type];
      return lm != null && lm.likelihood >= minLikelihood;
    }

    bool isInside(Offset offset) {
      if (offset == Offset.zero) return false;
      return checkRect.contains(offset);
    }

    if (isHorizontal) {
      // Đối với bài nằm ngang (Plank, Push-up), chỉ cần một trong hai bên cơ thể hiển thị và lọt vào khung
      // Sửa lỗi cúi/nằm
      final leftShoulderVisible = isVisible(PoseLandmarkType.leftShoulder);
      final leftHipVisible = isVisible(PoseLandmarkType.leftHip);
      final leftInside = leftShoulderVisible && leftHipVisible &&
                         isInside(getScreenOffset(PoseLandmarkType.leftShoulder)) &&
                         isInside(getScreenOffset(PoseLandmarkType.leftHip));

      // Bên phải: vai, hông, gối
      final rightShoulderVisible = isVisible(PoseLandmarkType.rightShoulder);
      final rightHipVisible = isVisible(PoseLandmarkType.rightHip);
      final rightInside = rightShoulderVisible && rightHipVisible &&
                          isInside(getScreenOffset(PoseLandmarkType.rightShoulder)) &&
                          isInside(getScreenOffset(PoseLandmarkType.rightHip));

      isBodyInFrame = leftInside || rightInside;
    } else {
      // Đối với các bài đứng dọc, yêu cầu thấy rõ cả 2 vai và 2 hông, và chúng nằm trong khung
      final shouldersVisible = isVisible(PoseLandmarkType.leftShoulder) &&
                               isVisible(PoseLandmarkType.rightShoulder);
      final hipsVisible = isVisible(PoseLandmarkType.leftHip) &&
                          isVisible(PoseLandmarkType.rightHip);

      if (shouldersVisible && hipsVisible) {
        final leftShoulderPos = getScreenOffset(PoseLandmarkType.leftShoulder);
        final rightShoulderPos = getScreenOffset(PoseLandmarkType.rightShoulder);
        final leftHipPos = getScreenOffset(PoseLandmarkType.leftHip);
        final rightHipPos = getScreenOffset(PoseLandmarkType.rightHip);

        isBodyInFrame = isInside(leftShoulderPos) &&
                        isInside(rightShoulderPos) &&
                        isInside(leftHipPos) &&
                        isInside(rightHipPos);

        // Nếu thấy cả đầu gối hoặc cổ chân thì kiểm tra thêm để khuyến khích đứng lùi lại
        final leftKneePos = getScreenOffset(PoseLandmarkType.leftKnee);
        final rightKneePos = getScreenOffset(PoseLandmarkType.rightKnee);
        if (isVisible(PoseLandmarkType.leftKnee) && isVisible(PoseLandmarkType.rightKnee)) {
          isBodyInFrame = isBodyInFrame && isInside(leftKneePos) && isInside(rightKneePos);
        }
      } else {
        isBodyInFrame = false;
      }
    }

    // 3. Sinh phản hồi tiếng Việt cụ thể và thân thiện
    String feedback = '';
    if (!isBodyInFrame) {
      if (isHorizontal) {
        feedback = 'Hãy nằm vào trong khung hình ngang trên sàn.';
      } else {
        // Kiểm tra xem người dùng có đứng quá gần không
        final leftShoulder = pose.landmarks[PoseLandmarkType.leftShoulder];
        final rightShoulder = pose.landmarks[PoseLandmarkType.rightShoulder];
        if (leftShoulder != null && rightShoulder != null) {
          final dist = (leftShoulder.x - rightShoulder.x).abs();
          // Nếu khoảng cách vai trên ảnh quá lớn -> Đang đứng quá gần
          if (dist > imageSize.width * 0.45) {
            feedback = 'Hãy đứng lùi lại để camera thấy toàn thân.';
          } else {
            feedback = 'Hãy di chuyển toàn bộ cơ thể vào trong khung hình.';
          }
        } else {
          feedback = 'Hãy đứng lùi lại và di chuyển vào trong khung hình.';
        }
      }
    } else {
      feedback = 'Đã nhận diện: ${getAngleName(currentAngle)}. Giữ nguyên vị trí...';
    }

    return AlignmentResult(
      isAligned: isBodyInFrame,
      currentAngle: currentAngle,
      currentYaw: yaw,
      feedbackMessage: feedback,
      isBodyInFrame: isBodyInFrame,
      isAngleCorrect: true,
    );
  }
}
