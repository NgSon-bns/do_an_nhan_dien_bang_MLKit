import 'package:flutter/material.dart';

enum ExerciseType { pushUp, squat, plank, jumpingJack }

class ExerciseDetail {
  final ExerciseType type;
  final String name;
  final String description;
  final IconData icon;
  final List<String> instructions;
  final bool isDurationBased;
  final int targetValue; // Số lần hoặc số giây mục tiêu
  final String difficulty;
  final double caloriesPerMin;

  static const List<int> targetOptions = [25, 20, 75, 100];

  const ExerciseDetail({
    required this.type,
    required this.name,
    required this.description,
    required this.icon,
    required this.instructions,
    required this.isDurationBased,
    required this.targetValue,
    required this.difficulty,
    required this.caloriesPerMin,
  });

  static List<int> computeSetPlan(int totalReps) {
    if (totalReps <= 0) return [];

    final double quarter = totalReps / 4.0;
    int sets = quarter >= 8 ? 4 : totalReps ~/ 8;
    if (sets < 1) {
      sets = 1;
    }

    final int baseCount = totalReps ~/ sets;
    final int remainder = totalReps % sets;

    return List<int>.generate(
      sets,
      (index) => baseCount + (index < remainder ? 1 : 0),
    );
  }

  static List<ExerciseDetail> get defaultExercises {
    return const [
      ExerciseDetail(
        type: ExerciseType.pushUp,
        name: 'Chống Đẩy (Push-Up)',
        description: 'Bài tập phát triển cơ ngực, vai và bắp tay sau.',
        icon: Icons.fitness_center,
        isDurationBased: false,
        targetValue: 15,
        difficulty: 'Trung bình',
        caloriesPerMin: 8.5,
        instructions: [
          'Đặt hai tay rộng hơn vai một chút, thân người thẳng từ đầu đến gót chân.',
          'Hạ người xuống cho đến khi góc khuỷu tay nhỏ hơn 90 độ.',
          'Đẩy người thẳng lên vị trí ban đầu (khuỷu tay duỗi > 155 độ).',
          'Lưu ý: Giữ lưng thẳng, không để võng hoặc nhô hông cao quá.',
        ],
      ),
      ExerciseDetail(
        type: ExerciseType.squat,
        name: 'Squat (Gánh Đùi)',
        description: 'Phát triển cơ đùi trước, cơ mông và cơ đùi sau.',
        icon: Icons.accessibility_new,
        isDurationBased: false,
        targetValue: 20,
        difficulty: 'Dễ',
        caloriesPerMin: 7.0,
        instructions: [
          'Đứng thẳng, hai chân rộng bằng vai, mũi chân hướng nhẹ ra ngoài.',
          'Hạ hông xuống như đang ngồi vào ghế, gập đầu gối tối thiểu dưới 100 độ.',
          'Giữ ngực cao, không cúi gập lưng quá nhiều (> 45 độ so với phương thẳng đứng).',
          'Đẩy gót chân lên để đứng thẳng dậy vị trí cũ.',
        ],
      ),
      ExerciseDetail(
        type: ExerciseType.plank,
        name: 'Plank (Tấm Ván)',
        description: 'Tập trung gồng cơ bụng core và tăng sức bền cơ thể.',
        icon: Icons.timer,
        isDurationBased: true,
        targetValue: 60,
        difficulty: 'Trung bình',
        caloriesPerMin: 5.0,
        instructions: [
          'Đặt cẳng tay lên sàn, khuỷu tay vuông góc ngay dưới vai.',
          'Thân người song song mặt sàn, tạo thành đường thẳng từ vai đến gót chân.',
          'Đồng hồ đếm thời gian chỉ tích lũy khi giữ tư thế lưng và hông thẳng.',
          'Cảnh báo sẽ nhấp nháy nếu hông của bạn quá cao hoặc võng quá thấp.',
        ],
      ),
      ExerciseDetail(
        type: ExerciseType.jumpingJack,
        name: 'Jumping Jack',
        description: 'Bài tập toàn thân cardio đốt cháy calo cực kỳ hiệu quả.',
        icon: Icons.directions_run,
        isDurationBased: false,
        targetValue: 25,
        difficulty: 'Dễ',
        caloriesPerMin: 10.0,
        instructions: [
          'Bắt đầu ở tư thế đứng khép chân, tay đặt hai bên đùi.',
          'Nhảy dạng rộng chân ra (gấp đôi chiều rộng vai) đồng thời giơ hai tay lên cao qua đầu.',
          'Nhảy ngược lại về tư thế khép chân, tay hạ xuống đùi để hoàn thành 1 lần.',
          'Thực hiện chuyển động nhịp nhàng và liên tục.',
        ],
      ),
    ];
  }
}
