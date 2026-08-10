import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

class ImageBakingService {
  
  
  Future<File> bakeSkeleton({
    required File originalImageFile,
    required Map<String, Offset> landmarks, 
    required double streamWidth,
    required double streamHeight,
    required String exerciseId,
    required String errorMessage,
    required bool isPostureCorrect,
    int sensorOrientation = 90,
    bool isFrontCamera = false,
  }) async {
    try {
      
      final Uint8List imageBytes = await originalImageFile.readAsBytes();
      final ui.Codec codec = await ui.instantiateImageCodec(
        imageBytes,
        targetWidth: 720, 
      );
      final ui.FrameInfo frameInfo = await codec.getNextFrame();
      final ui.Image rawImage = frameInfo.image;

      final double imageWidth = rawImage.width.toDouble();
      final double imageHeight = rawImage.height.toDouble();

      
      final Map<String, Offset> scaledLandmarks = {};
      landmarks.forEach((key, pt) {
        double rx = pt.dx;
        double ry = pt.dy;
        
        double px = 0.0;
        double py = 0.0;

        if (sensorOrientation == 90) {
          
          px = ry;
          py = rx;
        } else if (sensorOrientation == 270) {
          
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

        
        final bool isRotated = (sensorOrientation == 90 || sensorOrientation == 270);
        final double scaleX = imageWidth / (isRotated ? streamHeight : streamWidth);
        final double scaleY = imageHeight / (isRotated ? streamWidth : streamHeight);

        scaledLandmarks[key] = Offset(px * scaleX, py * scaleY);
      });

      
      final ui.PictureRecorder recorder = ui.PictureRecorder();
      final Canvas canvas = Canvas(recorder);

      
      canvas.drawImage(rawImage, Offset.zero, Paint());



      
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
