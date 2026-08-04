import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

class ImageBakingService {
  
  /// Vẽ khung xương, đường gióng chuẩn lý thuyết và cảnh báo lên ảnh chụp gốc
  Future<File> bakeSkeleton({
    required File originalImageFile,
    required Map<String, Offset> landmarks, // Tọa độ tỷ lệ tương đối trên stream
    required double streamWidth,
    required double streamHeight,
    required String exerciseId,
    required String errorMessage,
    required bool isPostureCorrect,
    int sensorOrientation = 90,
    bool isFrontCamera = false,
  }) async {
    try {
      // 1. Đọc bytes và giải mã ảnh chụp gốc với kích thước tối ưu để tránh tràn bộ nhớ (OOM)
      final Uint8List imageBytes = await originalImageFile.readAsBytes();
      final ui.Codec codec = await ui.instantiateImageCodec(
        imageBytes,
        targetWidth: 720, // Giới hạn chiều rộng tối đa 720px để tránh tràn RAM (OOM)
      );
      final ui.FrameInfo frameInfo = await codec.getNextFrame();
      final ui.Image rawImage = frameInfo.image;

      final double imageWidth = rawImage.width.toDouble();
      final double imageHeight = rawImage.height.toDouble();

      // 2. Chuyển đổi và xoay tọa độ khớp xương dựa trên độ xoay cảm biến và đối xứng camera trước để khớp ảnh chụp chân dung
      final Map<String, Offset> scaledLandmarks = {};
      landmarks.forEach((key, pt) {
        double rx = pt.dx;
        double ry = pt.dy;
        
        double px = 0.0;
        double py = 0.0;

        if (sensorOrientation == 90) {
          // Xoay 90 độ xuôi chiều kim đồng hồ (Thường là camera sau)
          px = ry;
          py = rx;
        } else if (sensorOrientation == 270) {
          // Xoay 270 độ (Thường là camera trước)
          if (isFrontCamera) {
            px = streamHeight - ry;
            py = rx;
          } else {
            px = streamHeight - ry;
            py = streamWidth - rx;
          }
        } else {
          px = rx;
          py = ry;
        }

        // Tính tỷ lệ phóng to phù hợp với kích thước ảnh chụp thực tế đứng (xoay dọc) hoặc ngang
        final bool isRotated = (sensorOrientation == 90 || sensorOrientation == 270);
        final double scaleX = imageWidth / (isRotated ? streamHeight : streamWidth);
        final double scaleY = imageHeight / (isRotated ? streamWidth : streamHeight);

        scaledLandmarks[key] = Offset(px * scaleX, py * scaleY);
      });

      // 3. Khởi tạo canvas ghi hình
      final ui.PictureRecorder recorder = ui.PictureRecorder();
      final Canvas canvas = Canvas(recorder);

      // Vẽ bức ảnh gốc làm nền
      canvas.drawImage(rawImage, Offset.zero, Paint());



      // 6. VẼ KHUNG TEXTBOX ĐÓNG DẤU CẢNH BÁO LỖI (Baking Text Warning)
      final double fontSize = max(16.0, imageWidth * 0.035);
      final textPainter = TextPainter(
        text: TextSpan(
          text: ' ⚠️ CẢNH BÁO TƯ THẾ SAI: $errorMessage ',
          style: TextStyle(
            color: Colors.white,
            fontSize: fontSize,
            fontWeight: FontWeight.bold,
            height: 1.4,
            backgroundColor: Colors.red.withValues(alpha: 0.85),
          ),
        ),
        textDirection: TextDirection.ltr,
      );
      textPainter.layout(maxWidth: imageWidth * 0.9);
      
      // Vẽ nền đen mờ sau chữ để dễ nhìn
      final double textX = 20.0;
      final double textY = imageHeight - textPainter.height - 40.0;
      
      canvas.drawRect(
        Rect.fromLTWH(
          textX - 10, 
          textY - 10, 
          textPainter.width + 20, 
          textPainter.height + 20
        ),
        Paint()..color = Colors.black.withValues(alpha: 0.6)
      );

      textPainter.paint(canvas, Offset(textX, textY));

      // 7. Kết xuất Canvas thành tệp tin hình ảnh mới
      final ui.Picture picture = recorder.endRecording();
      final ui.Image finalImage = await picture.toImage(rawImage.width, rawImage.height);
      final ByteData? byteData = await finalImage.toByteData(format: ui.ImageByteFormat.png);
      
      if (byteData == null) return originalImageFile;
      final Uint8List pngBytes = byteData.buffer.asUint8List();

      final directory = await getTemporaryDirectory();
      final String path = '${directory.path}/baked_${DateTime.now().millisecondsSinceEpoch}.png';
      final File bakedFile = File(path);
      await bakedFile.writeAsBytes(pngBytes);

      return bakedFile;
    } catch (e) {
      debugPrint('Lỗi dựng hình khung xương: $e');
      return originalImageFile;
    }
  }

}
