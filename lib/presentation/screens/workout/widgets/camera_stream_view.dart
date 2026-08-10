import 'package:flutter/material.dart';
import 'package:camera/camera.dart';

class CameraStreamView extends StatelessWidget {
  final CameraController controller;

  const CameraStreamView({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    
    
    var scale = size.aspectRatio * controller.value.aspectRatio;

    if (scale < 1) {
      scale = 1 / scale;
    }

    return ClipRRect(
      child: Stack(
        fit: StackFit.expand,
        children: [
          Transform.scale(
            scale: scale,
            child: Center(
              child: CameraPreview(controller),
            ),
          ),
        ],
      ),
    );
  }
}
