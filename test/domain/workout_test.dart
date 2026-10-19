import 'package:flutter_test/flutter_test.dart';
import 'package:simplerunning/domain/workout.dart';

void main() {
  test('four rounds include four recoveries and optional warmup/cooldown', () {
    final recipe = WorkoutRecipe.intervals();
    expect(recipe.blocks.where((b) => b.kind == BlockKind.run), hasLength(4));
    expect(
      recipe.blocks.where((b) => b.kind == BlockKind.recovery),
      hasLength(4),
    );
    expect(recipe.seconds, 1560);
    expect(() => WorkoutRecipe.intervals(rounds: 0), throwsArgumentError);
    expect(() => WorkoutRecipe.intervals(run: -1), throwsArgumentError);
  });
  test('late timer callbacks use elapsed time rather than tick count', () {
    final runner = WorkoutRunner(
      WorkoutRecipe.intervals(
        rounds: 2,
        run: 10,
        recovery: 5,
        warmup: 0,
        cooldown: 0,
      ),
    );
    expect(runner.update(9, 0), isFalse);
    expect(runner.remaining(9), 1);
    expect(runner.update(16, 0), isTrue);
    expect(runner.index, 2);
    expect(runner.remaining(16), 9);
    expect(runner.update(30, 0), isTrue);
    expect(runner.finished, isTrue);
  });
  test(
    'distance goal begins at its own baseline and does not finish on time',
    () {
      final runner = WorkoutRunner(
        const WorkoutRecipe('test', 'test', [
          WorkoutBlock(BlockKind.warmup, 'warm', seconds: 10),
          WorkoutBlock(BlockKind.run, 'run', meters: 1000),
          WorkoutBlock(BlockKind.cooldown, 'cool', seconds: 10),
        ]),
      );
      runner.update(10, 100);
      expect(runner.remainingMeters(400), 700);
      runner.update(2000, 1090);
      expect(runner.index, 1);
      runner.update(2010, 1100);
      expect(runner.index, 2);
      expect(runner.remaining(2010), 10);
      runner.update(2020, 1110);
      expect(runner.finished, isTrue);
    },
  );
  test('extend and skip mark session adapted and retain clock boundaries', () {
    final runner = WorkoutRunner(
      WorkoutRecipe.intervals(
        rounds: 1,
        run: 10,
        recovery: 5,
        warmup: 0,
        cooldown: 0,
      ),
    );
    runner.extend();
    expect(runner.remaining(10), 30);
    expect(runner.modified, isTrue);
    runner.skip(12, 20);
    expect(runner.remaining(12), 5);
    runner.update(17, 20);
    expect(runner.finished, isTrue);
    expect(runner.modified, isTrue);
  });
  test('free training never auto-completes and plan ids are unique', () {
    final runner = WorkoutRunner(WorkoutRecipe.free);
    runner.update(999999, 999999);
    expect(runner.finished, isFalse);
    final sessions = runningPlans.expand((p) => p.sessions).toList();
    expect(sessions, hasLength(51));
    expect(sessions.map((s) => s.id).toSet(), hasLength(51));
    expect(
      sessions.every(
        (s) => s.blocks.every((b) => b.seconds > 0 || b.meters > 0),
      ),
      isTrue,
    );
    expect(runningPlans.last.sessions.last.meters, 10000);
  });
}
