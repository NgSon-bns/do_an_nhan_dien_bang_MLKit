import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import 'pose_analysis_result.dart';

abstract class BasePoseEvaluator {
  /// Khởi động lại (Reset) các biến đếm, trạng thái chuyển động của bài tập
  void reset();

  /// Phân tích tư thế từ pose landmark của Google ML Kit và trả về kết quả đánh giá
  PoseAnalysisResult evaluate(Pose pose);
}
