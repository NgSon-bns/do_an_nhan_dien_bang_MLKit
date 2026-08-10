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

  
  int activeHoldSeconds;

  final List<String> _recordedMistakes = [];

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
    _recordedMistakes.clear();
  }

  void updateCalories(double caloriesPerMin, {required bool isDurationBased}) {
    if (isDurationBased) {
      
      double minutes = activeHoldSeconds / 60.0;
      caloriesBurned = minutes * caloriesPerMin;
    } else {
      
      
      
      double caloriesPerRep = caloriesPerMin / 20.0;
      caloriesBurned = counter * caloriesPerRep;
    }
  }

  void recordMistake(String mistake) {
    _recordedMistakes.add(mistake);
  }

  WorkoutMistakeSummary getMistakeSummary() {
    final Map<String, int> counts = {};
    for (final mistake in _recordedMistakes) {
      counts[mistake] = (counts[mistake] ?? 0) + 1;
    }

    String? mostFrequent;
    int maxCount = 0;
    counts.forEach((mistake, count) {
      if (count > maxCount) {
        maxCount = count;
        mostFrequent = mistake;
      }
    });

    return WorkoutMistakeSummary(
      totalMistakes: _recordedMistakes.length,
      mistakeCounts: counts,
      mostFrequentMistake: mostFrequent,
    );
  }
}

class WorkoutMistakeSummary {
  final int totalMistakes;
  final Map<String, int> mistakeCounts;
  final String? mostFrequentMistake;

  WorkoutMistakeSummary({
    required this.totalMistakes,
    required this.mistakeCounts,
    this.mostFrequentMistake,
  });
}

