class WorkoutSession {
  int counter;
  int elapsedSeconds;
  int incorrectPostureCount;
  bool isPostureCorrect;
  String feedbackMessage;
  double caloriesBurned;
  
  // Dành riêng cho Plank: thời gian giữ plank chuẩn
  int activeHoldSeconds;

  WorkoutSession({
    this.counter = 0,
    this.elapsedSeconds = 0,
    this.incorrectPostureCount = 0,
    this.isPostureCorrect = true,
    this.feedbackMessage = 'Sẵn sàng! Hãy vào đúng tư thế.',
    this.caloriesBurned = 0.0,
    this.activeHoldSeconds = 0,
  });

  void reset() {
    counter = 0;
    elapsedSeconds = 0;
    incorrectPostureCount = 0;
    isPostureCorrect = true;
    feedbackMessage = 'Sẵn sàng! Hãy vào đúng tư thế.';
    caloriesBurned = 0.0;
    activeHoldSeconds = 0;
  }

  void updateCalories(double caloriesPerMin) {
    // Nếu là bài tập tính thời gian (Plank), tính theo activeHoldSeconds
    // Nếu là các bài tập đếm lần, tính theo tổng thời gian elapsedSeconds
    double minutes = elapsedSeconds / 60.0;
    caloriesBurned = minutes * caloriesPerMin;
  }
}
