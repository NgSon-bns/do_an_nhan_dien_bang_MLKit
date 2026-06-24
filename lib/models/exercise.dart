import 'package:flutter/material.dart';

enum ExerciseType { pushUp, squat, plank, jumpingJack, burpee, walkingLunge }

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
      ExerciseDetail(
        type: ExerciseType.burpee,
        name: 'Burpee',
        description:
            'Bài tập toàn thân kết hợp cardio và sức mạnh, đốt cháy calo rất hiệu quả.',
        icon: Icons.fitness_center,
        isDurationBased: false,
        targetValue: 15,
        difficulty: 'Khó',
        caloriesPerMin: 12.5,
        instructions: [
          'Đứng thẳng, hai chân rộng bằng vai.',
          'Cúi xuống squats, đặt hai tay lên mặt sàn.',
          'Nhảy hoặc bước chân ra phía sau để tạo tư thế plank, thân người thẳng.',
          'Nhảy hoặc bước chân quay lại phía trước, quay trở lại tư thế squat.',
          'Nhảy thẳng lên với tay giơ cao trên đầu để hoàn thành 1 lần.',
        ],
      ),
      ExerciseDetail(
        type: ExerciseType.walkingLunge,
        name: 'Walking Lunge',
        description:
            'Bài tập bước gập gối di chuyển phát triển cơ đùi và cơ mông.',
        icon: Icons.directions_walk,
        isDurationBased: false,
        targetValue: 20,
        difficulty: 'Trung bình',
        caloriesPerMin: 8.0,
        instructions: [
          'Đứng thẳng, hai chân rộng bằng hông, tay đặt hai bên sườn hoặc hông.',
          'Bước một chân lớn về phía trước và hạ hông xuống cho đến khi đùi chân trước song song với sàn (góc gối trước ~ 90 độ).',
          'Đầu gối chân sau cũng gập lại và hướng thẳng xuống sàn nhưng không chạm sàn (góc gối sau ~ 90 độ).',
          'Giữ thân người thẳng đứng, không cúi nghiêng lưng ra trước.',
          'Đẩy gót chân trước đứng dậy bước tiếp chân sau lên trước để bắt đầu rep mới.',
        ],
      ),
    ];
  }
}
