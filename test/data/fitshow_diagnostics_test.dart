import 'package:flutter_test/flutter_test.dart';
import 'package:simplerunning/data/fitshow_diagnostics.dart';

void main() {
  test('workout parser preserves raw distance and rejects invalid packets', () {
    final payload = [0x52, 0, 0x34, 0x12, 0x78, 0x56, 0, 0, 0, 0];
    final bytes = [2, ...payload, payload.fold(0, (a, b) => a ^ b), 3];
    final sample = FitShowWorkout.parse(bytes)!;
    expect(sample.elapsedSeconds, 0x1234);
    expect(sample.distanceRaw, 0x5678);
    expect(FitShowWorkout.parse(bytes.sublist(0, 8)), isNull);
    bytes[3] ^= 1;
    expect(FitShowWorkout.parse(bytes), isNull);
    expect(FitShowWorkout.parse([2, 0x51, 0, 0x51, 3]), isNull);
  });

  test('diagnostic requests contain only information/data/status commands', () {
    expect(FitShowQuery.speed.bytes, [2, 0x52, 2, 0x50, 3]);
    expect(FitShowQuery.status.bytes, [2, 0x51, 0x51, 3]);
    expect(FitShowQuery.workout.bytes, [2, 0x52, 0, 0x52, 3]);
    expect(FitShowQuery.speedLimits.bytes, [2, 0x50, 2, 0x52, 3]);
    for (final query in FitShowQuery.values) {
      expect(query.bytes[1], isNot(0x53));
    }
  });

  test(
    'status recognition rejects corruption, truncation and other commands',
    () {
      expect(isFitShowStatus([2, 0x51, 3, 0x52, 3]), isTrue);
      expect(isFitShowStatus([2, 0x51, 3, 0, 3]), isFalse);
      expect(isFitShowStatus([2, 0x51, 3]), isFalse);
      expect(isFitShowStatus([2, 0x52, 0, 0x52, 3]), isFalse);
    },
  );

  test('FTMS speed respects presence flag, little endian and hundredths', () {
    expect(treadmillSpeed([0x84, 4, 0x7b, 0x02]), 6.35);
    expect(treadmillSpeed([0x84, 4, 0, 0]), 0);
    expect(treadmillSpeed([0x85, 4, 0x7b, 0x02]), isNull);
    expect(treadmillSpeed([0, 0, 1]), isNull);
  });
}
