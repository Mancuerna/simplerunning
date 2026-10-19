import '../data/training_store.dart';

class TrainingStats {
  TrainingStats(this.sessions, DateTime now)
    : today = DateTime(now.year, now.month, now.day);
  final List<TrainingSession> sessions;
  final DateTime today;
  double get meters => sessions.fold(0, (sum, s) => sum + s.meters);
  int get seconds => sessions.fold(0, (sum, s) => sum + s.seconds);
  double get averageKmh => seconds > 0 ? meters / seconds * 3.6 : 0;
  double get longestMeters =>
      sessions.fold(0, (best, s) => s.meters > best ? s.meters : best);
  List<DateTime> get days => [
    for (var i = 6; i >= 0; i--)
      DateTime(today.year, today.month, today.day - i),
  ];
  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
  List<double> get dailyMeters => [
    for (final day in days)
      sessions
          .where((s) => _sameDay(s.started.toLocal(), day))
          .fold(0.0, (sum, s) => sum + s.meters),
  ];
  List<TrainingSession> get thisWeek => sessions.where((s) {
    final start = DateTime(
      today.year,
      today.month,
      today.day - today.weekday + 1,
    );
    final end = DateTime(today.year, today.month, today.day + 1);
    return !s.started.toLocal().isBefore(start) &&
        s.started.toLocal().isBefore(end);
  }).toList();
  Set<String> get completedRecipes => sessions
      .where((s) => s.complete && s.goalReached)
      .map((s) => s.recipeId)
      .toSet();
}
