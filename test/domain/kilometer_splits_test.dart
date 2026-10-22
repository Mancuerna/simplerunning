import 'package:flutter_test/flutter_test.dart';
import 'package:simplerunning/domain/kilometer_splits.dart';

// Two complete kilometers (6:00 and 5:00) and a faster 250 m finish.
List<Map<String, dynamic>> sampleRun() => [
  for (var t = 0; t <= 720; t += 5)
    {
      'seconds': t,
      'meters': t <= 360
          ? t / 360 * 1000
          : t <= 660
          ? 1000 + (t - 360) / 300 * 1000
          : 2000 + (t - 660) / 60 * 250,
    },
];

void main() {
  test('ranks complete kilometers and keeps the final partial separate', () {
    final splits = KilometerSplits.fromSamples(sampleRun());
    expect(splits.completed.map((s) => s.seconds), [360, 300]);
    expect(splits.fastest!.number, 2);
    expect(splits.fastest!.speedKmh, 12);
    expect(splits.partial!.meters, 250);
    expect(splits.partial!.seconds, 60);
    expect(splits.partial!.speedKmh, closeTo(15, .0001));
    expect(splits.partial!.complete, isFalse);
    expect(splits.hasGaps, isFalse);
  });

  test('interpolates the kilometer boundary between readings', () {
    final splits = KilometerSplits();
    for (var t = 0; t <= 300; t += 5) {
      splits.add(t.toDouble(), t * 3);
    }
    for (var t = 305; t <= 335; t += 5) {
      splits.add(t.toDouble(), t * 3);
    }
    expect(splits.completed.single.seconds, closeTo(1000 / 3, .0001));
    expect(splits.partial!.meters, 5);
    expect(splits.partial!.seconds, closeTo(5 / 3, .0001));
  });

  test('missing samples cannot create a best kilometer', () {
    final splits = KilometerSplits.fromSamples([
      {'seconds': 0, 'meters': 0},
      {'seconds': 600, 'meters': 2000},
    ]);
    expect(splits.completed, hasLength(2));
    expect(splits.completed.every((s) => !s.reliable), isTrue);
    expect(splits.fastest, isNull);
    expect(splits.hasGaps, isTrue);
  });

  test('truncated recordings do not invent an origin or a best split', () {
    final splits = KilometerSplits.fromSamples([
      {'seconds': 600, 'meters': 1900},
      {'seconds': 605, 'meters': 2000},
    ]);
    expect(splits.completed.single.number, 2);
    expect(splits.fastest, isNull);
  });

  test('duplicates are harmless and invalid readings invalidate their lap', () {
    final splits = KilometerSplits.fromSamples(sampleRun());
    splits.add(720, 2250);
    expect(splits.hasGaps, isFalse);
    splits.add(double.nan, 2250);
    splits.add(715, 2200);
    expect(splits.partial!.reliable, isFalse);
    expect(splits.fastest!.number, 2);
    expect(splits.hasGaps, isTrue);
  });

  test('empty and subkilometer sessions have no best kilometer', () {
    expect(KilometerSplits().partial, isNull);
    final splits = KilometerSplits.fromSamples(sampleRun().take(20).toList());
    expect(splits.fastest, isNull);
    expect(splits.completed, isEmpty);
    expect(splits.partial, isNotNull);
  });
}
