// FitShow framing and query identifiers cross-checked against:
// https://github.com/cagnulein/qdomyos-zwift/blob/master/src/devices/fitshowtreadmill/fitshowtreadmill.h
// https://github.com/cagnulein/qdomyos-zwift/blob/master/src/devices/fitshowtreadmill/fitshowtreadmill.cpp
// FitShow framing and read-only diagnostic queries.
enum FitShowQuery {
  status([0x51]),
  workout([0x52, 0x00]),
  speedLimits([0x50, 0x02]),
  speed([0x52, 0x02]);

  const FitShowQuery(this._payload);
  final List<int> _payload;

  List<int> get bytes => [
    0x02,
    ..._payload,
    _payload.fold(0, (checksum, byte) => checksum ^ byte),
    0x03,
  ];
}

List<int>? fitShowPayload(List<int> bytes) {
  if (bytes.length < 4 || bytes.first != 2 || bytes.last != 3) return null;
  final payload = bytes.sublist(1, bytes.length - 2);
  if (payload.fold(0, (checksum, byte) => checksum ^ byte) !=
      bytes[bytes.length - 2]) {
    return null;
  }
  return payload;
}

bool isFitShowStatus(List<int> bytes) {
  final payload = fitShowPayload(bytes);
  return payload != null && payload.length >= 2 && payload.first == 0x51;
}

bool matchesFitShowQuery(FitShowQuery query, List<int> bytes) {
  final payload = fitShowPayload(bytes);
  if (payload == null || payload.length < 2) return false;
  return payload[0] == query._payload[0] &&
      (query == FitShowQuery.status || payload[1] == query._payload[1]);
}

class FitShowWorkout {
  const FitShowWorkout(this.elapsedSeconds, this.distanceRaw);
  final int elapsedSeconds;
  // Workout counter: meters, reported in increments of 10.
  final int distanceRaw;

  static FitShowWorkout? parse(List<int> bytes) {
    final payload = fitShowPayload(bytes);
    if (payload == null ||
        payload.length < 10 ||
        payload[0] != 0x52 ||
        payload[1] != 0) {
      return null;
    }
    return FitShowWorkout(
      payload[2] | payload[3] << 8,
      payload[4] | payload[5] << 8,
    );
  }
}

// FTMS Treadmill Data: bit 0 clear means instantaneous speed is present.
// Keep absent speed distinct from a reported zero.
double? treadmillSpeed(List<int> bytes) {
  if (bytes.length < 4 || bytes[0] & 1 != 0) return null;
  return (bytes[2] | bytes[3] << 8) / 100;
}

List<int> fitShowFrame(List<int> payload) => [
  2,
  ...payload,
  payload.fold(0, (a, b) => a ^ b),
  3,
];

List<int> fitShowClock(DateTime now) => fitShowFrame([
  0x50,
  0,
  now.year % 100,
  now.month,
  now.day,
  now.hour,
  now.minute,
  now.second,
]);

class FitShowStatus {
  const FitShowStatus(this.state, this.speedKmh, this.elapsedSeconds);
  final int state;
  final double? speedKmh;
  final int? elapsedSeconds;
  static FitShowStatus? parse(List<int> bytes) {
    final p = fitShowPayload(bytes);
    if (p == null || p.length < 2 || p[0] != 0x51) return null;
    final running = p[1] == 3;
    return FitShowStatus(
      p[1],
      running ? (p.length >= 13 ? p[2] / 10 : null) : 0,
      p.length >= 13 ? p[4] | p[5] << 8 : null,
    );
  }
}
