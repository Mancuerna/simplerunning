enum BlockKind { warmup, run, recovery, cooldown }

class WorkoutBlock {
  const WorkoutBlock(
    this.kind,
    this.label, {
    this.seconds = 0,
    this.meters = 0,
  });
  final BlockKind kind;
  final String label;
  final int seconds;
  final double meters;
  Map<String, Object> toJson() => {
    'kind': kind.name,
    'label': label,
    'seconds': seconds,
    'meters': meters,
  };
}

class WorkoutRecipe {
  const WorkoutRecipe(this.id, this.title, this.blocks, {this.subtitle = ''});
  final String id;
  final String title;
  final String subtitle;
  final List<WorkoutBlock> blocks;
  bool get isFree => blocks.isEmpty;
  int get seconds => blocks.fold(0, (sum, block) => sum + block.seconds);
  double get meters => blocks.fold(0, (sum, block) => sum + block.meters);
  Map<String, Object> toJson() => {
    'id': id,
    'title': title,
    'blocks': blocks.map((b) => b.toJson()).toList(),
  };
  static const free = WorkoutRecipe(
    'free',
    'A tu ritmo',
    [],
    subtitle: 'Sin reloj de llegada. Solo tú y la cinta.',
  );

  static WorkoutRecipe intervals({
    int rounds = 4,
    int run = 120,
    int recovery = 120,
    int warmup = 300,
    int cooldown = 300,
  }) {
    if (rounds < 1 ||
        rounds > 30 ||
        run < 5 ||
        run > 3600 ||
        recovery < 5 ||
        recovery > 3600 ||
        warmup < 0 ||
        warmup > 1800 ||
        cooldown < 0 ||
        cooldown > 1800) {
      throw ArgumentError('Invalid interval configuration');
    }
    return WorkoutRecipe('intervals', '$rounds tandas', [
      if (warmup > 0)
        WorkoutBlock(BlockKind.warmup, 'Calienta caminando', seconds: warmup),
      for (var i = 1; i <= rounds; i++) ...[
        WorkoutBlock(
          BlockKind.run,
          'Corre · tanda $i de $rounds',
          seconds: run,
        ),
        WorkoutBlock(
          BlockKind.recovery,
          'Recupera · tanda $i de $rounds',
          seconds: recovery,
        ),
      ],
      if (cooldown > 0)
        WorkoutBlock(
          BlockKind.cooldown,
          'Vuelve a la calma',
          seconds: cooldown,
        ),
    ], subtitle: '$rounds bloques de carrera y $rounds de recuperación');
  }
}

/// Uses active session time, never timer ticks. Late callbacks cannot extend time blocks.
class WorkoutRunner {
  WorkoutRunner(this.recipe);
  final WorkoutRecipe recipe;
  int index = 0;
  int startSecond = 0;
  double startMeters = 0;
  int extraSeconds = 0;
  bool modified = false;
  bool skipped = false;
  bool get finished => !recipe.isFree && index >= recipe.blocks.length;
  WorkoutBlock? get current =>
      recipe.isFree || finished ? null : recipe.blocks[index];
  int remaining(int seconds) => current == null
      ? 0
      : (current!.seconds + extraSeconds - (seconds - startSecond)).clamp(
          0,
          1000000,
        );
  double remainingMeters(double meters) => current == null
      ? 0
      : (current!.meters - (meters - startMeters)).clamp(0, double.infinity);

  bool update(int seconds, double meters) {
    final before = index;
    while (current != null) {
      final block = current!;
      final reached = block.meters > 0
          ? meters - startMeters >= block.meters
          : seconds - startSecond >= block.seconds + extraSeconds;
      if (!reached) break;
      startSecond = block.meters > 0
          ? seconds
          : startSecond + block.seconds + extraSeconds;
      // Distance belongs to the next block only after its boundary is observed.
      startMeters = meters;
      extraSeconds = 0;
      index++;
    }
    return index != before;
  }

  void skip(int seconds, double meters) {
    if (current == null) return;
    modified = true;
    skipped = true;
    index++;
    startSecond = seconds;
    startMeters = meters;
    extraSeconds = 0;
  }

  void extend() {
    if (current == null || current!.meters > 0) return;
    extraSeconds += 30;
    modified = true;
  }
}

class RunningPlan {
  const RunningPlan(this.id, this.title, this.description, this.weeks);
  final String id;
  final String title;
  final String description;
  final List<List<WorkoutRecipe>> weeks;
  List<WorkoutRecipe> get sessions => weeks.expand((w) => w).toList();
}

// Original templates, not a reproduction of a branded C25K programme.
// Three outings per week, with repeatable weeks and no prescribed speed.
final runningPlans = [
  RunningPlan(
    '5k',
    'Camino a los 5K',
    'Empieza alternando caminar y correr. 9 semanas orientativas, 3 sesiones por semana y un día de descanso entre ellas. Termina con 30 minutos continuos: la distancia dependerá de tu ritmo. Repite semanas cuando lo necesites.',
    [
      for (var week = 0; week < 9; week++)
        [for (var day = 0; day < 3; day++) _beginnerSession(week, day)],
    ],
  ),
  RunningPlan(
    '10k',
    'De 5 a 10K',
    'Para cuando ya corres 5 km con comodidad. 8 semanas orientativas, 3 sesiones suaves por semana y descanso entre ellas. La salida larga crece poco a poco; puedes repetir cualquier semana.',
    [
      for (var week = 0; week < 8; week++)
        [
          for (var day = 0; day < 3; day++)
            WorkoutRecipe(
              '10k-w${week + 1}-d${day + 1}',
              '10K · semana ${week + 1}, día ${day + 1}',
              [
                const WorkoutBlock(
                  BlockKind.warmup,
                  'Calienta caminando',
                  seconds: 300,
                ),
                WorkoutBlock(
                  BlockKind.run,
                  'Carrera suave',
                  meters:
                      (day == 2
                          ? [5.5, 6.0, 6.5, 5.5, 7.0, 8.0, 9.0, 10.0][week]
                          : day == 0
                          ? 4.0
                          : 5.0) *
                      1000,
                ),
                const WorkoutBlock(
                  BlockKind.cooldown,
                  'Vuelve a la calma',
                  seconds: 300,
                ),
              ],
              subtitle: day == 2
                  ? 'Salida larga · ritmo cómodo'
                  : 'Construye continuidad',
            ),
        ],
    ],
  ),
];

WorkoutRecipe _beginnerSession(int week, int day) {
  const rounds = [8, 6, 6, 5, 4, 3, 2, 1, 1];
  const run = [60, 90, 120, 180, 300, 480, 720, 1500, 1800];
  const recovery = [90, 120, 120, 120, 120, 120, 180, 0, 0];
  return WorkoutRecipe(
    '5k-w${week + 1}-d${day + 1}',
    '5K · semana ${week + 1}, día ${day + 1}',
    [
      const WorkoutBlock(BlockKind.warmup, 'Calienta caminando', seconds: 300),
      for (var i = 0; i < rounds[week]; i++) ...[
        WorkoutBlock(
          BlockKind.run,
          'Corre suave · ${i + 1}/${rounds[week]}',
          seconds: run[week],
        ),
        if (i < rounds[week] - 1)
          WorkoutBlock(
            BlockKind.recovery,
            'Camina y recupera',
            seconds: recovery[week],
          ),
      ],
      const WorkoutBlock(BlockKind.cooldown, 'Vuelve a la calma', seconds: 300),
    ],
    subtitle: week < 7
        ? 'Alterna carrera y caminata'
        : 'Carrera continua a tu ritmo',
  );
}
