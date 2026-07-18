class RecommendedMeal {
  final String key;
  final String timeLabel;
  final String description;
  final int calories;
  final List<String> ingredients;

  RecommendedMeal({
    required this.key,
    required this.timeLabel,
    required this.description,
    required this.calories,
    required this.ingredients,
  });
}
