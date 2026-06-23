class WorkoutSession {
  int counter;
  int elapsedSeconds;
  int incorrectPostureCount;
  bool isPostureCorrect;
  bool isResting;
  int restSecondsLeft;
  String feedbackMessage;
  String announcementMessage;
  double caloriesBurned;

  // Dành riêng cho Plank: thời gian giữ plank chuẩn
  int activeHoldSeconds;

  WorkoutSession({
    this.counter = 0,
    this.elapsedSeconds = 0,
    this.incorrectPostureCount = 0,
    this.isPostureCorrect = true,
    this.isResting = false,
    this.restSecondsLeft = 0,
    this.feedbackMessage = 'Sẵn sàng! Hãy vào đúng tư thế.',
    this.announcementMessage = '',
    this.caloriesBurned = 0.0,
    this.activeHoldSeconds = 0,
  });

  void reset() {
    counter = 0;
    elapsedSeconds = 0;
    incorrectPostureCount = 0;
    isPostureCorrect = true;
    isResting = false;
    restSecondsLeft = 0;
    feedbackMessage = 'Sẵn sàng! Hãy vào đúng tư thế.';
    announcementMessage = '';
    caloriesBurned = 0.0;
    activeHoldSeconds = 0;
  }

  void updateCalories(double caloriesPerMin, {required bool isDurationBased}) {
    if (isDurationBased) {
      // Đối với bài tập tính thời gian (Plank), tính theo activeHoldSeconds (thời gian giữ chuẩn)
      double minutes = activeHoldSeconds / 60.0;
      caloriesBurned = minutes * caloriesPerMin;
    } else {
      // Đối với các bài tập đếm lần (Squat, Chống đẩy, Jumping Jack)
      // Tính calo trực tiếp dựa trên số lần tập thành công (reps)
      // Giả định tốc độ tập trung bình chuẩn là 20 reps/phút
      double caloriesPerRep = caloriesPerMin / 20.0;
      caloriesBurned = counter * caloriesPerRep;
    }
  }
}
