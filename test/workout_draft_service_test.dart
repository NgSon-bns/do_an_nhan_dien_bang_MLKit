import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:demo/services/workout_draft_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
  });

  test('saves and restores today draft workout', () async {
    final service = WorkoutDraftService();

    await service.saveDraftWorkout(
      exerciseType: 'pushUp',
      exerciseName: 'Chống đẩy',
      targetCount: 50,
      noSplit: false,
      sourceTag: 'recommendation',
    );

    final draft = await service.getTodayDraftWorkout();
    expect(draft, isNotNull);
    expect(draft!['exerciseType'], 'pushUp');
    expect(draft['exerciseName'], 'Chống đẩy');
    expect(draft['targetCount'], 50);
    expect(draft['completedCount'], 0);
    expect(draft['sourceTag'], 'recommendation');
  });

  test('saves today draft workout with non-zero completed count', () async {
    final service = WorkoutDraftService();

    await service.saveDraftWorkout(
      exerciseType: 'squat',
      exerciseName: 'Squat',
      targetCount: 30,
      noSplit: true,
      completedCount: 12,
      sourceTag: 'exercise_list',
    );

    final draft = await service.getTodayDraftWorkout();
    expect(draft, isNotNull);
    expect(draft!['exerciseType'], 'squat');
    expect(draft['completedCount'], 12);
  });

  test('clears draft after completion', () async {
    final service = WorkoutDraftService();
    await service.saveDraftWorkout(
      exerciseType: 'squat',
      exerciseName: 'Squat',
      targetCount: 30,
      noSplit: true,
      sourceTag: 'exercise_list',
    );

    await service.clearTodayDraftWorkout();
    final draft = await service.getTodayDraftWorkout();
    expect(draft, isNull);
  });
}
