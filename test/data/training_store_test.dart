import 'dart:io';
import 'dart:convert';

import 'package:simplerunning/domain/workout.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:simplerunning/data/training_store.dart';
import 'package:simplerunning/data/fitshow_diagnostics.dart';

void main() {
  test('pause excludes movement and resume establishes a fresh baseline', () {
    final dir = Directory.systemTemp.createTempSync('pause_store_');
    addTearDown(() => dir.deleteSync(recursive: true));
    final store = TrainingStore(dir)..start(100);
    store.distance(120);
    store.pause();
    expect(store.recording, isTrue);
    expect(store.paused, isTrue);
    store.distance(150);
    store.sample(10);
    store.resume();
    store.distance(180);
    store.distance(190);
    store.finish(complete: true);
    expect(store.load().single.meters, 30);
    expect(store.load().single.events.map((e) => e['type']), [
      'pause',
      'resume',
    ]);
  });

  test('backup roundtrip preserves metadata, skips duplicates and ignores source filenames', () {
    final dir = Directory.systemTemp.createTempSync('backup_store_');
    addTearDown(() => dir.deleteSync(recursive: true));
    final original = TrainingStore(Directory('${dir.path}/source'));
    original.start(0, recipe: runningPlans.first.sessions.first);
    original.distance(50);
    original.sample(5);
    original.finish(complete: true, goalReached: true);
    final backup = original.exportAll().readAsStringSync();
    final destination = TrainingStore(Directory('${dir.path}/destination'));
    expect(destination.importBackup(backup), 1);
    expect(destination.importBackup(backup), 0);
    final restored = destination.load().single;
    expect(restored.meters, 50);
    expect(restored.recipeId, '5k-w1-d1');
    expect(restored.goalReached, isTrue);
    final data = jsonDecode(backup) as Map<String, dynamic>;
    (data['sessions'] as List).first['filename'] = '../../escaped.jsonl';
    expect(destination.importBackup(jsonEncode(data)), 0);
    expect(File('${dir.path}/escaped.jsonl').existsSync(), isFalse);
    expect(
      original.exportCsv(original.load().single).readAsStringSync(),
      contains('seconds,meters,speed_kmh,phase'),
    );
  });

  test('invalid backup is rejected before writing any sessions', () {
    final dir = Directory.systemTemp.createTempSync('invalid_backup_');
    addTearDown(() => dir.deleteSync(recursive: true));
    final store = TrainingStore(dir);
    final start = jsonEncode({
      'type': 'training_start',
      'utc': '2026-01-01T00:00:00Z',
    });
    expect(
      () => store.importBackup(
        jsonEncode({
          'schema': 1,
          'sessions': [
            {'jsonl': start},
            {'jsonl': 'broken'},
          ],
        }),
      ),
      throwsFormatException,
    );
    expect(store.load(), isEmpty);
  });

  test('saves distance deltas, console resets and missing speed without inventing zero', () {
    final dir = Directory.systemTemp.createTempSync('training_test_');
    addTearDown(() => dir.deleteSync(recursive: true));
    final store = TrainingStore(dir)..start(100);
    store.distance(120);
    store.sample(6);
    store.distance(120);
    store.distance(0);
    store.distance(10);
    store.sample(null);
    store.finish(complete: true);
    final session = TrainingStore(dir).load().single;
    expect(session.meters, 30);
    expect(session.complete, isTrue);
    expect(session.samples[1]['speed_kmh'], 6);
    expect(session.samples[2]['speed_kmh'], isNull);
  });

  test('recovers unfinished session and ignores truncated final line', () {
    final dir = Directory.systemTemp.createTempSync('training_recovery_');
    addTearDown(() => dir.deleteSync(recursive: true));
    final store = TrainingStore(dir)..start(null);
    store.distance(200);
    store.distance(210);
    store.sample(4);
    expect(TrainingStore(dir).load().single.meters, 10);
    expect(TrainingStore(dir).load().single.complete, isFalse);
    store.finish(complete: false);
    final file = store.load().single.file;
    file.writeAsStringSync('{"type":', mode: FileMode.append);
    expect(TrainingStore(dir).load().single.meters, 10);
    final restoredDir = Directory.systemTemp.createTempSync(
      'recovered_backup_',
    );
    addTearDown(() => restoredDir.deleteSync(recursive: true));
    final restored = TrainingStore(restoredDir);
    expect(restored.importBackup(store.exportAll().readAsStringSync()), 1);
    expect(restored.load().single.meters, 10);
  });

  test(
    'status parses speed and time, rejects corruption and clears stopped speed',
    () {
      final payload = [0x51, 3, 65, 0, 44, 1, 0, 0, 0, 0, 0, 0, 0];
      final state = FitShowStatus.parse(fitShowFrame(payload))!;
      expect(state.speedKmh, 6.5);
      expect(state.elapsedSeconds, 300);
      payload[1] = 1;
      expect(FitShowStatus.parse(fitShowFrame(payload))!.speedKmh, 0);
      expect(FitShowStatus.parse(fitShowFrame([0x51, 3]))!.speedKmh, isNull);
      final corrupt = fitShowFrame(payload)..[3] = 1;
      expect(FitShowStatus.parse(corrupt), isNull);
    },
  );
}
