import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:simplerunning/data/training_store.dart';
import 'package:simplerunning/domain/training_stats.dart';

TrainingSession session(
  DateTime date,
  int seconds,
  double meters, {
  bool complete = true,
  bool reached = false,
}) => TrainingSession(
  File('synthetic'),
  date,
  [
    {'seconds': seconds, 'meters': meters, 'speed_kmh': 6.0},
  ],
  complete,
  recipeId: '5k-w1-d1',
  goalReached: reached,
);
void main() {
  test('weekly totals cross month boundaries and incomplete goals never advance plans', () {
    final stats = TrainingStats([
      session(DateTime(2026, 9, 28), 100, 200, reached: true),
      session(DateTime(2026, 10, 1), 200, 400, complete: false),
      session(DateTime(2026, 9, 27), 100, 100),
    ], DateTime(2026, 10, 1));
    expect(stats.thisWeek, hasLength(2));
    expect(stats.dailyMeters.reduce((a, b) => a + b), 700);
    expect(stats.completedRecipes, {'5k-w1-d1'});
    expect(stats.averageKmh, closeTo(6.3, .001));
    expect(stats.longestMeters, 400);
  });
  test('saved early training does not complete a plan', () {
    expect(
      TrainingStats([
        session(DateTime(2026), 30, 20),
      ], DateTime(2026)).completedRecipes,
      isEmpty,
    );
  });
}
