import '../../models/exercise.dart';
import 'base_pose_evaluator.dart';
import 'push_up_evaluator.dart';
import 'squat_evaluator.dart';
import 'plank_evaluator.dart';
import 'jumping_jack_evaluator.dart';

class EvaluatorFactory {
  /// Hàm Factory khởi tạo đối tượng phân tích phù hợp với từng bài tập
  static BasePoseEvaluator create(ExerciseType type) {
    switch (type) {
      case ExerciseType.pushUp:
        return PushUpEvaluator();
      case ExerciseType.squat:
        return SquatEvaluator();
      case ExerciseType.plank:
        return PlankEvaluator();
      case ExerciseType.jumpingJack:
        return JumpingJackEvaluator();
    }
  }
}
