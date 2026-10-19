import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

class CaptureLog {
  CaptureLog(this.directory);
  final Directory directory;
  RandomAccessFile? _output;
  final Stopwatch _clock = Stopwatch();
  int _sequence = 0;
  File? file;

  void start() {
    close();
    directory.createSync(recursive: true);
    file = File(
      p.join(
        directory.path,
        'capture_${DateTime.now().toUtc().microsecondsSinceEpoch}.jsonl',
      ),
    );
    _output = file!.openSync(mode: FileMode.write);
    _sequence = 0;
    _clock
      ..reset()
      ..start();
    add('session_start', {'schema': 1});
  }

  void add(String type, [Map<String, Object?> data = const {}]) {
    final output = _output;
    if (output == null) return;
    output.writeStringSync(
      '${jsonEncode({'seq': _sequence++, 'utc': DateTime.now().toUtc().toIso8601String(), 'elapsed_us': _clock.elapsedMicroseconds, 'type': type, ...data})}\n',
    );
    // Persist each event so a killed app leaves a usable partial capture.
    output.flushSync();
  }

  void close() {
    _output?.closeSync();
    _output = null;
    _clock.stop();
  }

  List<File> sessions() {
    if (!directory.existsSync()) return [];
    return directory
        .listSync()
        .whereType<File>()
        .where((f) => p.extension(f.path) == '.jsonl')
        .toList()
      ..sort((a, b) => b.path.compareTo(a.path));
  }
}
