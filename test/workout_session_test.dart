import 'package:flutter_test/flutter_test.dart';
import 'package:demo/models/workout_session.dart';

void main() {
  group('WorkoutSession mistake summary', () {
    test('counts mistakes and returns the most frequent one', () {
      final session = WorkoutSession();
      session.recordMistake('Đặt chân quá rộng');
      session.recordMistake('Đặt chân quá rộng');
      session.recordMistake('Cột sống cong');
      session.recordMistake('Cột sống cong');
      session.recordMistake('Cột sống cong');

      final summary = session.getMistakeSummary();

      expect(summary.totalMistakes, 5);
      expect(summary.mistakeCounts['Đặt chân quá rộng'], 2);
      expect(summary.mistakeCounts['Cột sống cong'], 3);
      expect(summary.mostFrequentMistake, 'Cột sống cong');
    });
  });
}
