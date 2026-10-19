import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:simplerunning/data/capture_log.dart';

void main() {
  late Directory directory;
  late CaptureLog log;
  setUp(() {
    directory = Directory.systemTemp.createTempSync('capture_test_');
    log = CaptureLog(directory);
  });
  tearDown(() {
    log.close();
    directory.deleteSync(recursive: true);
  });

  test('each event is readable before closing, with lossless raw bytes and markers', () {
    log.start();
    log.add('read', {'hex': '000aff80'});
    log.add('marker', {'label': 'Cambio\nvelocidad "rápida"'});
    final rows = log.file!
        .readAsLinesSync()
        .map((s) => jsonDecode(s) as Map<String, dynamic>)
        .toList();
    expect(rows.length, 3);
    expect(rows[1]['hex'], '000aff80');
    expect(rows[2]['label'], 'Cambio\nvelocidad "rápida"');
    expect(rows.map((r) => r['seq']), [0, 1, 2]);
    expect(
      rows[2]['elapsed_us'] as int,
      greaterThanOrEqualTo(rows[1]['elapsed_us'] as int),
    );
  });

  test(
    'new sessions preserve old captures and can be recovered after restart',
    () {
      log.start();
      final first = log.file!;
      log.add('marker', {'label': 'first'});
      log.close();
      log.start();
      log.add('marker', {'label': 'second'});
      log.close();
      expect(CaptureLog(directory).sessions().length, 2);
      expect(first.readAsStringSync(), contains('first'));
      expect(first.readAsStringSync(), isNot(contains('second')));
    },
  );
}
