import 'dart:math' as math;
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

class PoseMath {
  /// Tính góc ở đỉnh B tạo bởi 3 điểm A, B, C (ví dụ: Vai - Khuỷu tay - Cổ tay)
static double calculateAngle(PoseLandmark a, PoseLandmark b, PoseLandmark c) {
  // Tính góc của từng đoạn thẳng so với trục ngang
  double radians = math.atan2(c.y - b.y, c.x - b.x) - math.atan2(a.y - b.y, a.x - b.x);
  
  // Chuyển sang độ
  double angle = radians * 180.0 / math.pi;
  
  // Chuẩn hóa góc về khoảng [0, 360)
  if (angle < 0) {
    angle += 360.0;
  }
  
  return angle;
}

  /// Tính khoảng cách Euclidean giữa 2 điểm
  static double calculateDistance(PoseLandmark a, PoseLandmark b) {
    return math.sqrt(math.pow(a.x - b.x, 2) + math.pow(a.y - b.y, 2));
  }

  /// Tính góc nghiêng của đoạn thẳng AB so với phương thẳng đứng (trục Y)
  /// Thích hợp để tính góc nghiêng của lưng (Vai - Hông)
  static double calculateAngleToVertical(PoseLandmark a, PoseLandmark b) {
    double dx = (a.x - b.x).abs();
    double dy = (a.y - b.y).abs();
    if (dy == 0) return 90.0;
    double radians = math.atan(dx / dy);
    return radians * 180.0 / math.pi;
  }

  /// Tính góc nghiêng của đoạn thẳng AB so với phương nằm ngang (trục X)
  /// Thích hợp để tính độ ngang của cơ thể khi tập Plank
  static double calculateAngleToHorizontal(PoseLandmark a, PoseLandmark b) {
    double dx = (a.x - b.x).abs();
    double dy = (a.y - b.y).abs();
    if (dx == 0) return 90.0;
    double radians = math.atan(dy / dx);
    return radians * 180.0 / math.pi;
  }
}
