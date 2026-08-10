import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import 'package:demo/domain/exercise.dart';

enum CameraAngle {
  front,          
  diagonalLeft,   
  diagonalRight,  
  side,           
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
      if (dx > 5) { 
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

  
  static bool isHorizontalLayout(ExerciseType exerciseType) {
    
    if (exerciseType == ExerciseType.plank || exerciseType == ExerciseType.push_up) {
      return true;
    }
    return false;
  }

  
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

    
    final isHorizontal = isHorizontalLayout(exerciseType);
    final double boxWidth;
    final double boxHeight;
    final double boxLeft;
    final double boxTop;

    if (isHorizontal) {
      
      boxWidth = screenSize.width * 0.90;
      boxHeight = screenSize.height * 0.45;
      boxLeft = (screenSize.width - boxWidth) / 2;
      boxTop = (screenSize.height - boxHeight) / 2 + 60; 
    } else {
      
      boxWidth = screenSize.width * 0.65;
      boxHeight = screenSize.height * 0.80;
      boxLeft = (screenSize.width - boxWidth) / 2;
      boxTop = (screenSize.height - boxHeight) / 2;
    }

    final frameRect = Rect.fromLTWH(boxLeft, boxTop, boxWidth, boxHeight);

    
    final toleranceX = boxWidth * 0.15;
    final toleranceY = boxHeight * 0.15;
    final checkRect = Rect.fromLTRB(
      frameRect.left - toleranceX,
      frameRect.top - toleranceY,
      frameRect.right + toleranceX,
      frameRect.bottom + toleranceY,
    );

    
    bool isBodyInFrame = false;
    const double minLikelihood = 0.45; 

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
      
      
      final leftShoulderVisible = isVisible(PoseLandmarkType.leftShoulder);
      final leftHipVisible = isVisible(PoseLandmarkType.leftHip);
      final leftInside = leftShoulderVisible && leftHipVisible &&
                         isInside(getScreenOffset(PoseLandmarkType.leftShoulder)) &&
                         isInside(getScreenOffset(PoseLandmarkType.leftHip));

      
      final rightShoulderVisible = isVisible(PoseLandmarkType.rightShoulder);
      final rightHipVisible = isVisible(PoseLandmarkType.rightHip);
      final rightInside = rightShoulderVisible && rightHipVisible &&
                          isInside(getScreenOffset(PoseLandmarkType.rightShoulder)) &&
                          isInside(getScreenOffset(PoseLandmarkType.rightHip));

      isBodyInFrame = leftInside || rightInside;
    } else {
      
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

        
        final leftKneePos = getScreenOffset(PoseLandmarkType.leftKnee);
        final rightKneePos = getScreenOffset(PoseLandmarkType.rightKnee);
        if (isVisible(PoseLandmarkType.leftKnee) && isVisible(PoseLandmarkType.rightKnee)) {
          isBodyInFrame = isBodyInFrame && isInside(leftKneePos) && isInside(rightKneePos);
        }
      } else {
        isBodyInFrame = false;
      }
    }

    
    String feedback = '';
    if (!isBodyInFrame) {
      if (isHorizontal) {
        feedback = 'Hãy nằm vào trong khung hình ngang trên sàn.';
      } else {
        
        final leftShoulder = pose.landmarks[PoseLandmarkType.leftShoulder];
        final rightShoulder = pose.landmarks[PoseLandmarkType.rightShoulder];
        if (leftShoulder != null && rightShoulder != null) {
          final dist = (leftShoulder.x - rightShoulder.x).abs();
          
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
