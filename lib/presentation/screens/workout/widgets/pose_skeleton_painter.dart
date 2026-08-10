import 'package:flutter/material.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

class PoseSkeletonPainter extends CustomPainter {
  final Pose pose;
  final Size imageSize;
  final InputImageRotation rotation;
  final bool isFrontCamera;
  
  
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
