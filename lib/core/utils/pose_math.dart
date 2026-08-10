import 'dart:math' as math;
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

class PoseMath {
  
static double calculateAngle(PoseLandmark a, PoseLandmark b, PoseLandmark c) {
  
  double radians = math.atan2(c.y - b.y, c.x - b.x) - math.atan2(a.y - b.y, a.x - b.x);
  
  
  double angle = radians * 180.0 / math.pi;
  
  
  if (angle < 0) {
    angle += 360.0;
  }
  
  return angle;
}

static double getElbowAngle(PoseLandmark s, PoseLandmark e, PoseLandmark w) {
  double angle = PoseMath.calculateAngle(s, e, w);
  return angle > 180 ? 360 - angle : angle;
}

  
  static double calculateDistance(PoseLandmark a, PoseLandmark b) {
    return math.sqrt(math.pow(a.x - b.x, 2) + math.pow(a.y - b.y, 2));
  }

  
  
  static double calculateAngleToVertical(PoseLandmark a, PoseLandmark b) {
    double dx = (a.x - b.x).abs();
    double dy = (a.y - b.y).abs();
    if (dy == 0) return 90.0;
    double radians = math.atan(dx / dy);
    return radians * 180.0 / math.pi;
  }

  
  
  static double calculateAngleToHorizontal(PoseLandmark a, PoseLandmark b) {
    double dx = (a.x - b.x).abs();
    double dy = (a.y - b.y).abs();
    if (dx == 0) return 90.0;
    double radians = math.atan(dy / dx);
    return radians * 180.0 / math.pi;
  }
}
