class KilometerSplit {
  const KilometerSplit({
    required this.number,
    required this.meters,
    required this.seconds,
    required this.complete,
    required this.reliable,
  });

  final int number;
  final double meters;
  final double seconds;
  final bool complete;
  final bool reliable;
  double? get speedKmh =>
      reliable && seconds > 0 && meters > 0 ? meters / seconds * 3.6 : null;
}

class KilometerSplits {
  KilometerSplits();

  factory KilometerSplits.fromSamples(List<Map<String, dynamic>> samples) {
    final result = KilometerSplits();
    for (final sample in samples) {
      final seconds = sample['seconds'];
      final meters = sample['meters'];
      if (seconds is num && meters is num) {
        result.add(seconds.toDouble(), meters.toDouble());
      } else {
        result._lapReliable = false;
        result.hasGaps = true;
      }
    }
    return result;
  }

  final List<KilometerSplit> _completed = [];
  List<KilometerSplit> get completed => List.unmodifiable(_completed);
  double _seconds = 0;
  double _meters = 0;
  double _lapStartSeconds = 0;
  int _nextKilometer = 1;
  bool _started = false;
  bool _lapReliable = true;
  bool hasGaps = false;

  int get currentNumber => _nextKilometer;
  double get currentMeters => _meters - (_nextKilometer - 1) * 1000;
  double get currentSeconds => _seconds - _lapStartSeconds;
  KilometerSplit? get partial => currentMeters > 0
      ? KilometerSplit(
          number: currentNumber,
          meters: currentMeters,
          seconds: currentSeconds,
          complete: false,
          reliable: _lapReliable,
        )
      : null;

  KilometerSplit? get fastest {
    KilometerSplit? best;
    for (final split in _completed) {
      if (split.speedKmh == null) continue;
      if (best == null || split.seconds < best.seconds) best = split;
    }
    return best;
  }

  void add(double seconds, double meters) {
    if (!seconds.isFinite ||
        !meters.isFinite ||
        seconds < 0 ||
        meters < 0 ||
        (_started && (seconds < _seconds || meters < _meters))) {
      hasGaps = true;
      _lapReliable = false;
      return;
    }
    if (!_started) {
      _started = true;
      _seconds = seconds;
      _meters = meters;
      _lapStartSeconds = seconds;
      _nextKilometer = meters ~/ 1000 + 1;
      _lapReliable = seconds == 0 && meters == 0;
      hasGaps = !_lapReliable;
      return;
    }
    final dt = seconds - _seconds;
    final dm = meters - _meters;
    // Recording normally samples every second. Do not award a best split
    // across a missing stretch of samples or an instantaneous distance jump.
    final segmentReliable = dt <= 10 && (dt > 0 || dm == 0);
    if (dt > 10) {
      _lapReliable = false;
      hasGaps = true;
    }
    while (meters >= _nextKilometer * 1000 && dm > 0) {
      final boundary = _nextKilometer * 1000;
      final crossedAt = _seconds + (boundary - _meters) / dm * dt;
      final reliable = _lapReliable && segmentReliable;
      if (!reliable) hasGaps = true;
      _completed.add(
        KilometerSplit(
          number: _nextKilometer,
          meters: 1000,
          seconds: crossedAt - _lapStartSeconds,
          complete: true,
          reliable: reliable,
        ),
      );
      _lapStartSeconds = crossedAt;
      _nextKilometer++;
      _lapReliable = segmentReliable;
    }
    _seconds = seconds;
    _meters = meters;
  }
}
