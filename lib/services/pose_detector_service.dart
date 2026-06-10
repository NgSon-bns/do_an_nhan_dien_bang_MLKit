import 'dart:io';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

class PoseDetectorService {
  PoseDetector? _poseDetector;

  /// Khởi tạo PoseDetector với cấu hình tối ưu cho luồng Stream trực tiếp
  void initialize() {
    _poseDetector = PoseDetector(
      options: PoseDetectorOptions(
        model: PoseDetectionModel.base,
        mode: PoseDetectionMode.stream,
      ),
    );
  }

  /// Xử lý chuyển đổi CameraImage từ Camera stream thành InputImage và chạy AI nhận diện tư thế
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

    // Kiểm tra định dạng ảnh tương ứng với từng hệ điều hành
    if (format == null ||
        (Platform.isAndroid && format != InputImageFormat.nv21) ||
        (Platform.isIOS && format != InputImageFormat.bgra8888)) {
      return [];
    }

    // Đảm bảo dữ liệu ảnh chỉ có 1 mặt phẳng (đặc trưng của NV21 và BGRA8888 trên di động)
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

  /// Giải phóng bộ nhớ của PoseDetector
  Future<void> close() async {
    await _poseDetector?.close();
    _poseDetector = null;
  }
}
