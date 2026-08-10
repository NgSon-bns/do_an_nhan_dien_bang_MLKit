import 'dart:io';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

class PoseDetectorService {
  PoseDetector? _poseDetector;

  
  void initialize() {
    _poseDetector = PoseDetector(
      options: PoseDetectorOptions(
        model: PoseDetectionModel.base,
        mode: PoseDetectionMode.stream,
      ),
    );
  }

  
  Future<List<Pose>> processCameraImage(
    CameraImage image,
    CameraController cameraController,
  ) async {
    if (_poseDetector == null) {
      return [];
    }

    final format = InputImageFormatValue.fromRawValue(
      image.format.raw as int? ?? 0,
    );

    
    if (format == null ||
        (Platform.isAndroid && format != InputImageFormat.nv21) ||
        (Platform.isIOS && format != InputImageFormat.bgra8888)) {
      return [];
    }

    
    if (image.planes.length != 1) {
      return [];
    }

    final plane = image.planes.first;
    final rotation =
        InputImageRotationValue.fromRawValue(
              cameraController.description.sensorOrientation,
            ) ??
            InputImageRotation.rotation0deg;

    final inputImage = InputImage.fromBytes(
      bytes: plane.bytes,
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: rotation,
        format: format,
        bytesPerRow: plane.bytesPerRow,
      ),
    );

    try {
      return await _poseDetector!.processImage(inputImage);
    } catch (e) {
      debugPrint('Lỗi xử lý ảnh bằng ML Kit: $e');
      return [];
    }
  }

  
  Future<void> close() async {
    await _poseDetector?.close();
    _poseDetector = null;
  }
}
