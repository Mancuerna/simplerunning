import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../domain/workout.dart';
import 'capture_log.dart';

class TrainingSession {
  TrainingSession(
    this.file,
    this.started,
    this.samples,
    this.complete, {
    this.title = 'Entrenamiento libre',
    this.recipeId = 'free',
    this.goalReached = false,
    this.events = const [],
  });
  final File file;
  final DateTime started;
  final List<Map<String, dynamic>> samples;
  final List<Map<String, dynamic>> events;
  final bool complete;
  final String title;
  final String recipeId;
  final bool goalReached;
  int get seconds =>
      samples.isEmpty ? 0 : (samples.last['seconds'] as num).toInt();
  double get meters =>
      samples.isEmpty ? 0 : (samples.last['meters'] as num).toDouble();
  double get averageKmh => seconds == 0 ? 0 : meters / seconds * 3.6;
  double get peakKmh => samples.fold(0, (peak, sample) {
    final speed = (sample['speed_kmh'] as num?)?.toDouble() ?? 0;
    return speed > peak ? speed : peak;
  });
  List<PhaseSummary> get phases {
    final grouped = <int, PhaseSummary>{};
    for (var i = 1; i < samples.length; i++) {
      final previous = samples[i - 1];
      final sample = samples[i];
      final index = previous['phase_index'] as int?;
      if (index == null) continue;
      final phase = grouped.putIfAbsent(
        index,
        () => PhaseSummary(
          previous['phase_label'] as String? ?? 'Bloque ${index + 1}',
        ),
      );
      final dt =
          (sample['seconds'] as num).toInt() -
          (previous['seconds'] as num).toInt();
      final dm =
          (sample['meters'] as num).toDouble() -
          (previous['meters'] as num).toDouble();
      if (dt >= 0) phase.seconds += dt;
      if (dm >= 0) phase.meters += dm;
    }
    return grouped.values.toList();
  }
}

class PhaseSummary {
  PhaseSummary(this.label);
  final String label;
  int seconds = 0;
  double meters = 0;
  double get speed => seconds == 0 ? 0 : meters / seconds * 3.6;
}

class TrainingStore {
  TrainingStore(Directory directory, {Stopwatch? clock})
    : _log = CaptureLog(directory),
      _clock = clock ?? Stopwatch();
  final CaptureLog _log;
  final Stopwatch _clock;
  bool _recording = false;
  bool get recording => _recording;
  bool get paused => recording && !_clock.isRunning;
  int get seconds => _clock.elapsed.inSeconds;
  double meters = 0;
  int? _lastDistance;
  Map<String, Object?> _phase = {};

  void start(int? distance, {WorkoutRecipe recipe = WorkoutRecipe.free}) {
    _log.start();
    _log.add('training_start', {
      'title': recipe.title,
      'recipe_id': recipe.id,
      'recipe': recipe.toJson(),
    });
    meters = 0;
    _lastDistance = distance;
    _phase = {};
    _recording = true;
    _clock
      ..reset()
      ..start();
    sample(null);
  }

  void distance(int value) {
    if (!recording) return;
    final previous = _lastDistance;
    if (!paused && previous != null && value >= previous) {
      meters += value - previous;
    }
    _lastDistance = value;
  }

  void setPhase(WorkoutRunner runner) {
    final block = runner.current;
    _phase = block == null
        ? {}
        : {
            'phase_index': runner.index,
            'phase_kind': block.kind.name,
            'phase_label': block.label,
          };
    event('phase', _phase);
  }

  void event(String type, [Map<String, Object?> data = const {}]) {
    if (recording) {
      _log.add(type, {'seconds': seconds, 'meters': meters, ...data});
    }
  }

  void pause() {
    if (!recording || paused) return;
    sample(null);
    _clock.stop();
    event('pause');
  }

  void resume() {
    if (!paused) return;
    // Avoid including any unobserved movement while paused.
    _lastDistance = null;
    event('resume');
    _clock.start();
  }

  void sample(double? speed) {
    if (!recording || paused) return;
    _log.add('sample', {
      'seconds': seconds,
      'meters': meters,
      'speed_kmh': speed,
      ..._phase,
    });
  }

  void finish({required bool complete, bool goalReached = false}) {
    if (!recording) return;
    sample(null);
    _log.add('training_end', {
      'complete': complete,
      'goal_reached': goalReached,
    });
    _clock.stop();
    _recording = false;
    _log.close();
  }

  List<TrainingSession> load() {
    final result = <TrainingSession>[];
    for (final file in _log.sessions()) {
      DateTime? started;
      final samples = <Map<String, dynamic>>[];
      final events = <Map<String, dynamic>>[];
      bool complete = false;
      bool goalReached = false;
      String title = 'Entrenamiento libre';
      String recipeId = 'free';
      for (final line in file.readAsLinesSync()) {
        try {
          final decoded = jsonDecode(line);
          if (decoded is! Map<String, dynamic>) continue;
          final event = decoded;
          if (event['type'] == 'training_start' && event['utc'] is String) {
            started = DateTime.parse(event['utc'] as String);
            title = event['title'] as String? ?? title;
            recipeId = event['recipe_id'] as String? ?? recipeId;
          }
          if (event['type'] == 'sample' &&
              event['seconds'] is num &&
              event['meters'] is num &&
              (event['speed_kmh'] == null || event['speed_kmh'] is num)) {
            samples.add(event);
          }
          if (event['type'] == 'training_end') {
            complete = event['complete'] == true;
            goalReached = event['goal_reached'] == true;
          }
          if ([
            'phase',
            'pause',
            'resume',
            'skip',
            'extend',
          ].contains(event['type'])) {
            events.add(event);
          }
        } on FormatException {
          // Preserve complete flushed records around a truncated write.
        } on TypeError {
          // One malformed record must not hide the rest of the history.
        }
      }
      if (started != null) {
        result.add(
          TrainingSession(
            file,
            started,
            samples,
            complete,
            title: title,
            recipeId: recipeId,
            goalReached: goalReached,
            events: events,
          ),
        );
      }
    }
    result.sort((a, b) => b.started.compareTo(a.started));
    return result;
  }

  File exportCsv(TrainingSession session) {
    final directory = Directory(p.join(_log.directory.parent.path, 'exports'))
      ..createSync(recursive: true);
    final file = File(
      p.join(
        directory.path,
        '${p.basenameWithoutExtension(session.file.path)}.csv',
      ),
    );
    String escape(Object? v) =>
        '"${(v ?? '').toString().replaceAll('"', '""')}"';
    file.writeAsStringSync(
      [
        'seconds,meters,speed_kmh,phase',
        for (final sample in session.samples)
          [
            sample['seconds'],
            sample['meters'],
            sample['speed_kmh'],
            sample['phase_label'],
          ].map(escape).join(','),
      ].join('\n'),
      flush: true,
    );
    return file;
  }

  int importBackup(String contents) {
    if (recording) throw StateError('Finish the session before restoring');
    if (contents.length > 20 * 1024 * 1024) {
      throw const FormatException('Backup too large');
    }
    final data = jsonDecode(contents);
    if (data is! Map<String, dynamic> ||
        data['schema'] != 1 ||
        data['sessions'] is! List) {
      throw const FormatException('Invalid backup');
    }
    final entries = data['sessions'] as List;
    if (entries.length > 1000) throw const FormatException('Too many sessions');
    final validated = <String>[];
    for (final entry in entries) {
      if (entry is! Map || entry['jsonl'] is! String) {
        throw const FormatException('Invalid session');
      }
      final jsonl = entry['jsonl'] as String;
      bool hasStart = false;
      int previousSecond = -1;
      final lines = const LineSplitter().convert(jsonl);
      for (var i = 0; i < lines.length; i++) {
        dynamic event;
        try {
          event = jsonDecode(lines[i]);
        } on FormatException {
          if (i == lines.length - 1 && !jsonl.endsWith('\n')) continue;
          rethrow;
        }
        if (event is! Map<String, dynamic>) {
          throw const FormatException('Invalid event');
        }
        if (event['type'] == 'training_start') {
          if (hasStart ||
              event['utc'] is! String ||
              DateTime.tryParse(event['utc'] as String) == null) {
            throw const FormatException('Invalid session start');
          }
          if ((event['title'] != null && event['title'] is! String) ||
              (event['recipe_id'] != null && event['recipe_id'] is! String)) {
            throw const FormatException('Invalid metadata');
          }
          hasStart = true;
        }
        if (event['type'] == 'sample') {
          final seconds = event['seconds'];
          final meters = event['meters'];
          final speed = event['speed_kmh'];
          if (seconds is! int ||
              seconds < previousSecond ||
              seconds < 0 ||
              meters is! num ||
              !meters.isFinite ||
              meters < 0 ||
              (speed != null &&
                  (speed is! num || !speed.isFinite || speed < 0))) {
            throw const FormatException('Invalid sample');
          }
          if ((event['phase_index'] != null && event['phase_index'] is! int) ||
              (event['phase_label'] != null &&
                  event['phase_label'] is! String)) {
            throw const FormatException('Invalid phase');
          }
          previousSecond = seconds;
        }
      }
      if (!hasStart) throw const FormatException('Missing session start');
      validated.add(jsonl);
    }
    // Validate everything before writing; never trust a supplied filename.
    _log.directory.createSync(recursive: true);
    final existing = _log.sessions().map((f) => f.readAsStringSync()).toSet();
    int imported = 0;
    final stamp = DateTime.now().toUtc().microsecondsSinceEpoch;
    for (final jsonl in validated) {
      if (!existing.add(jsonl)) continue;
      var name = 'capture_import_${stamp}_$imported';
      while (File(p.join(_log.directory.path, '$name.jsonl')).existsSync()) {
        name = '${name}_new';
      }
      final temp = File(p.join(_log.directory.path, '$name.tmp'));
      temp.writeAsStringSync(jsonl, flush: true);
      temp.renameSync(p.join(_log.directory.path, '$name.jsonl'));
      imported++;
    }
    return imported;
  }

  File exportAll() {
    final directory = Directory(p.join(_log.directory.parent.path, 'exports'))
      ..createSync(recursive: true);
    final file = File(p.join(directory.path, 'simplerunning-backup.json'));
    file.writeAsStringSync(
      jsonEncode({
        'schema': 1,
        'exported_utc': DateTime.now().toUtc().toIso8601String(),
        'sessions': [
          for (final session in load())
            {
              'filename': p.basename(session.file.path),
              'jsonl': session.file.readAsStringSync(),
            },
        ],
      }),
      flush: true,
    );
    return file;
  }
}
