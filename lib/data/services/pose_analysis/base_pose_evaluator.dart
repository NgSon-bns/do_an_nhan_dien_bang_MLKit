import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import 'pose_analysis_result.dart';

abstract class BasePoseEvaluator {
  
  void reset();

  
  PoseAnalysisResult evaluate(Pose pose);
}
