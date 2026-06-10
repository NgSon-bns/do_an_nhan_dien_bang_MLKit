class PoseAnalysisResult {
  final bool isPostureCorrect;
  final String feedbackMessage;
  final bool isBackCorrect;
  final bool isLegsCorrect;
  final bool isArmsCorrect;
  final bool shouldCountRep;

  PoseAnalysisResult({
    required this.isPostureCorrect,
    required this.feedbackMessage,
    this.isBackCorrect = true,
    this.isLegsCorrect = true,
    this.isArmsCorrect = true,
    this.shouldCountRep = false,
  });
}
