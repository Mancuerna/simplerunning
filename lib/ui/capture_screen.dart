import 'package:flutter/material.dart';

import '../domain/workout.dart';
import '../domain/training_stats.dart';
import 'app_theme.dart';
import 'capture_model.dart';
import 'interval_editor.dart';
import 'training_widgets.dart';

class CaptureScreen extends StatefulWidget {
  const CaptureScreen({super.key, required this.model});
  final CaptureModel model;
  @override
  State<CaptureScreen> createState() => _CaptureScreenState();
}

class _CaptureScreenState extends State<CaptureScreen>
    with WidgetsBindingObserver {
  int tab = 0;
  CaptureModel get model => widget.model;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) =>
      model.lifecycle(state.name);
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: model,
    builder: (context, _) => Scaffold(
      appBar: AppBar(
        title: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.route_rounded, color: lime),
            SizedBox(width: 10),
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  'simple running',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    letterSpacing: -1,
                  ),
                ),
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            onPressed: _settings,
            tooltip: 'Ajustes',
            icon: const Icon(Icons.tune_rounded),
          ),
        ],
      ),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (model.trainingActive)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
              child: Row(
                children: [
                  Expanded(
                    child: FilledButton(
                      onPressed: model.busy ? null : model.togglePause,
                      child: Text(model.paused ? 'Continuar' : 'Pausar'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: model.busy ? null : _confirmFinish,
                      child: const Text('Finalizar'),
                    ),
                  ),
                ],
              ),
            ),
          NavigationBar(
            selectedIndex: tab,
            onDestinationSelected: (index) => setState(() => tab = index),
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.play_circle_outline),
                selectedIcon: Icon(Icons.play_circle),
                label: 'Entrenar',
              ),
              NavigationDestination(
                icon: Icon(Icons.route_outlined),
                selectedIcon: Icon(Icons.route),
                label: 'Planes',
              ),
              NavigationDestination(
                icon: Icon(Icons.history),
                label: 'Historial',
              ),
              NavigationDestination(
                icon: Icon(Icons.bar_chart_rounded),
                label: 'Progreso',
              ),
            ],
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 740),
            child: ListView(
              key: ValueKey(tab),
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
              children: [
                if (model.trainingActive && tab != 0)
                  Card(
                    color: const Color(0xFF30402A),
                    child: ListTile(
                      onTap: () => setState(() => tab = 0),
                      leading: const Icon(Icons.directions_run, color: lime),
                      title: Text(
                        model.paused
                            ? 'Entrenamiento en pausa'
                            : 'Entrenamiento en marcha',
                      ),
                      trailing: const Icon(Icons.arrow_forward),
                    ),
                  ),
                if (model.error != null)
                  Card(
                    color: const Color(0xFF462C2C),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(model.error!),
                    ),
                  ),
                ...switch (tab) {
                  0 => _train(),
                  1 => _plans(),
                  2 => _history(),
                  _ => _progress(),
                },
              ],
            ),
          ),
        ),
      ),
    ),
  );

  List<Widget> _train() => [
    if (model.trainingActive)
      ..._live()
    else ...[
      _hero(),
      if (model.lastSavedMessage != null)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Text(
            model.lastSavedMessage!,
            style: const TextStyle(color: lime),
          ),
        ),
      const SectionHeading(
        'Hoy eliges tú',
        subtitle:
            'Una sesión libre, unas tandas o el siguiente paso de tu plan.',
      ),
      _choice(
        'A tu ritmo',
        'Entrenamiento libre',
        Icons.all_inclusive,
        model.selectedWorkout.isFree,
        () => model.selectWorkout(WorkoutRecipe.free),
      ),
      _choice(
        'Intervalos / HIIT',
        'Configura carrera y recuperación',
        Icons.timer_outlined,
        model.selectedWorkout.id == 'intervals',
        () => Navigator.push(
          context,
          MaterialPageRoute<void>(builder: (_) => IntervalEditor(model: model)),
        ),
      ),
      _choice(
        'Seguir un plan',
        'Camino a los 5K · De 5 a 10K',
        Icons.route_rounded,
        model.selectedWorkout.id.contains('-w'),
        () => setState(() => tab = 1),
      ),
      const SectionHeading('Tu cinta'),
      _connection(),
      const SizedBox(height: 12),
      FilledButton.icon(
        onPressed: model.canStartTraining ? model.startTraining : null,
        icon: const Icon(Icons.play_arrow_rounded),
        label: Text(model.busy ? 'Preparando…' : 'Empezar entrenamiento'),
      ),
      const Padding(
        padding: EdgeInsets.only(top: 12),
        child: Text(
          'Mantén la app abierta durante la sesión. La pantalla permanecerá encendida.',
          style: TextStyle(color: muted, fontSize: 12),
        ),
      ),
    ],
  ];

  Widget _hero() => Container(
    padding: const EdgeInsets.all(24),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(28),
      gradient: const LinearGradient(
        colors: [Color(0xFF283C2E), Color(0xFF17252C)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(
          children: [
            Icon(Icons.bolt, color: lime, size: 18),
            SizedBox(width: 6),
            Text(
              'TU PRÓXIMA SESIÓN',
              style: TextStyle(
                color: lime,
                letterSpacing: 1.5,
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        Text(
          model.selectedWorkout.title,
          style: const TextStyle(
            fontSize: 34,
            fontWeight: FontWeight.w800,
            height: 1.1,
            letterSpacing: -1,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          model.selectedWorkout.subtitle,
          style: const TextStyle(color: Color(0xFFCAD9CC), height: 1.5),
        ),
        const SizedBox(height: 24),
        Row(
          children: [
            const Icon(Icons.schedule, color: lime, size: 19),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _recipeDuration(model.selectedWorkout),
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            if (!model.selectedWorkout.isFree)
              IconButton(
                onPressed: () => _preview(model.selectedWorkout),
                tooltip: 'Ver bloques',
                icon: const Icon(Icons.format_list_bulleted),
              ),
          ],
        ),
      ],
    ),
  );

  Widget _choice(
    String title,
    String subtitle,
    IconData icon,
    bool selected,
    VoidCallback action,
  ) => Card(
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(20),
      side: BorderSide(color: selected ? lime : Colors.transparent),
    ),
    child: ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
      onTap: model.busy ? null : action,
      leading: Icon(icon, color: selected ? lime : muted),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: Text(subtitle, style: const TextStyle(color: muted)),
      trailing: Icon(
        selected ? Icons.check_circle : Icons.chevron_right,
        color: selected ? lime : muted,
      ),
    ),
  );

  Widget _connection() => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                model.active ? Icons.bluetooth_connected : Icons.bluetooth,
                color: model.active ? lime : muted,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  model.active ? 'Cinta conectada' : 'Conecta para empezar',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              if (model.active)
                IconButton(
                  onPressed: model.busy ? null : model.stop,
                  tooltip: 'Desconectar',
                  icon: const Icon(Icons.link_off),
                ),
            ],
          ),
          Text(
            model.status,
            style: const TextStyle(color: muted, fontSize: 12),
          ),
          if (!model.active) ...[
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: model.busy
                  ? null
                  : model.scanning
                  ? model.stopScan
                  : model.scan,
              icon: Icon(model.scanning ? Icons.stop : Icons.search),
              label: Text(model.scanning ? 'Detener búsqueda' : 'Buscar cinta'),
            ),
            if (model.scanning)
              const Padding(
                padding: EdgeInsets.only(top: 12),
                child: LinearProgressIndicator(),
              ),
            for (final device in model.devices)
              ListTile(
                contentPadding: EdgeInsets.zero,
                onTap: model.busy ? null : () => model.connect(device),
                title: Text(
                  device.name.isEmpty ? 'Dispositivo sin nombre' : device.name,
                ),
                subtitle: Text(
                  '${device.rssi} dBm',
                  style: const TextStyle(color: muted),
                ),
                trailing: const Icon(Icons.add_link),
              ),
          ],
          if (model.active && !model.polling && model.canQuery)
            TextButton(
              onPressed: model.retryPolling,
              child: const Text('Reintentar lectura de datos'),
            ),
        ],
      ),
    ),
  );

  List<Widget> _live() {
    final runner = model.runner;
    final block = runner?.current;
    final seconds = model.training?.seconds ?? 0;
    final meters = model.training?.meters ?? 0;
    final accent =
        block?.kind == BlockKind.recovery || block?.kind == BlockKind.cooldown
        ? recoveryBlue
        : lime;
    return [
      Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              model.paused ? 'EN PAUSA' : 'EN MARCHA',
              style: TextStyle(
                color: accent,
                letterSpacing: 2,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          IconButton(
            onPressed: () =>
                model.setPreference('voice', !model.preferences.voice),
            tooltip: 'Activar o silenciar avisos',
            icon: Icon(
              model.preferences.voice ? Icons.volume_up : Icons.volume_off,
            ),
          ),
        ],
      ),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                block?.label ?? 'A tu ritmo',
                style: TextStyle(
                  color: accent,
                  fontSize: 25,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 20),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  block == null
                      ? durationLabel(seconds)
                      : block.meters > 0
                      ? '${(runner!.remainingMeters(meters) / 1000).toStringAsFixed(2)} km'
                      : durationLabel(runner!.remaining(seconds)),
                  style: const TextStyle(
                    fontSize: 76,
                    height: 1,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -3,
                  ),
                ),
              ),
              Text(
                block == null ? 'tiempo activo' : 'para el siguiente bloque',
                style: const TextStyle(color: muted),
              ),
              if (block != null) ...[
                const SizedBox(height: 24),
                LinearProgressIndicator(
                  value: block.meters > 0
                      ? (1 - runner!.remainingMeters(meters) / block.meters)
                            .clamp(0, 1)
                      : (1 -
                                runner!.remaining(seconds) /
                                    (block.seconds + runner.extraSeconds))
                            .clamp(0, 1),
                  color: accent,
                  borderRadius: BorderRadius.circular(10),
                  minHeight: 8,
                ),
                const SizedBox(height: 12),
                Text(
                  'Bloque ${runner.index + 1} de ${runner.recipe.blocks.length}',
                  style: const TextStyle(color: muted),
                ),
                if (runner.index + 1 < runner.recipe.blocks.length)
                  Text(
                    'Después: ${runner.recipe.blocks[runner.index + 1].label}',
                    style: const TextStyle(color: muted),
                  ),
              ],
            ],
          ),
        ),
      ),
      TrainingMetrics(speed: model.liveSpeed, seconds: seconds, meters: meters),
      if (!model.speedFresh)
        const Padding(
          padding: EdgeInsets.all(8),
          child: Text(
            'Sin datos recientes de velocidad. Esperando a la cinta…',
            style: TextStyle(color: Colors.orangeAccent),
          ),
        ),
      if (model.workoutStale)
        const Text(
          'Distancia pendiente de actualizar.',
          style: TextStyle(color: Colors.orangeAccent),
        ),
      const SizedBox(height: 16),
      if (model.paused)
        const Padding(
          padding: EdgeInsets.all(8),
          child: Text(
            'Tiempo y distancia en pausa. La consola y la banda siguen independientes.',
            style: TextStyle(color: muted),
          ),
        ),
      if (block != null)
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 12,
          children: [
            if (block.seconds > 0)
              TextButton.icon(
                onPressed: model.busy ? null : model.extendBlock,
                icon: const Icon(Icons.more_time),
                label: const Text('+30 s'),
              ),
            TextButton.icon(
              onPressed: model.paused || model.busy ? null : _confirmSkip,
              icon: const Icon(Icons.skip_next),
              label: const Text('Saltar bloque'),
            ),
          ],
        ),
      const Padding(
        padding: EdgeInsets.only(top: 12),
        child: Text(
          'La parada finaliza la sesión de la consola; no frena físicamente la banda.',
          style: TextStyle(color: muted, fontSize: 12),
        ),
      ),
    ];
  }

  Future<void> _confirmFinish() async {
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('¿Guardamos hasta aquí?'),
        content: const Text('Conservarás todos los datos de esta sesión.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Seguir'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Guardar y finalizar'),
          ),
        ],
      ),
    );
    if (accepted == true) await model.finishTraining();
  }

  Future<void> _confirmSkip() async {
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('¿Pasar al siguiente bloque?'),
        content: const Text(
          'Se guardará como sesión adaptada y no completará automáticamente el objetivo del plan.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Volver'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Saltar'),
          ),
        ],
      ),
    );
    if (accepted == true) model.skipBlock();
  }

  List<Widget> _plans() {
    final completed = TrainingStats(
      model.history,
      DateTime.now(),
    ).completedRecipes;
    return [
      const SectionHeading(
        'Un paso más lejos.',
        subtitle: 'Constancia sin prisas. Elige el punto en el que estás.',
      ),
      for (final plan in runningPlans)
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  plan.id == '5k' ? 'EMPIEZA AQUÍ' : 'SIGUE CRECIENDO',
                  style: const TextStyle(
                    color: lime,
                    fontSize: 11,
                    letterSpacing: 2,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  plan.title,
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  plan.description,
                  style: const TextStyle(color: muted, height: 1.5),
                ),
                const SizedBox(height: 20),
                LinearProgressIndicator(
                  value:
                      plan.sessions
                          .where((s) => completed.contains(s.id))
                          .length /
                      plan.sessions.length,
                  borderRadius: BorderRadius.circular(8),
                ),
                const SizedBox(height: 8),
                Text(
                  '${plan.sessions.where((s) => completed.contains(s.id)).length} de ${plan.sessions.length} sesiones completadas',
                  style: const TextStyle(color: muted),
                ),
                const SizedBox(height: 14),
                FilledButton.icon(
                  onPressed: () => _preview(
                    plan.sessions.firstWhere(
                      (s) => !completed.contains(s.id),
                      orElse: () => plan.sessions.first,
                    ),
                  ),
                  icon: const Icon(Icons.play_arrow),
                  label: Text(
                    plan.sessions.every((s) => completed.contains(s.id))
                        ? 'Volver a empezar'
                        : 'Ver siguiente sesión',
                  ),
                ),
                for (var w = 0; w < plan.weeks.length; w++)
                  ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    title: Text('Semana ${w + 1}'),
                    subtitle: Text(
                      '${plan.weeks[w].where((s) => completed.contains(s.id)).length}/3 completadas',
                      style: const TextStyle(color: muted, fontSize: 12),
                    ),
                    children: [
                      for (var d = 0; d < plan.weeks[w].length; d++)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(
                            completed.contains(plan.weeks[w][d].id)
                                ? Icons.check_circle
                                : Icons.play_circle_outline,
                            color: completed.contains(plan.weeks[w][d].id)
                                ? lime
                                : muted,
                          ),
                          title: Text('Día ${d + 1}'),
                          subtitle: Text(_recipeDuration(plan.weeks[w][d])),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => _preview(plan.weeks[w][d]),
                        ),
                    ],
                  ),
              ],
            ),
          ),
        ),
      const Padding(
        padding: EdgeInsets.only(top: 16),
        child: Text(
          'Plantillas propias de SimpleRunning. El plan inicial desarrolla el tiempo de carrera, como los programas caminar/correr; 30 minutos no equivalen necesariamente a 5 km. Ajusta o repite las semanas a tu ritmo.',
          style: TextStyle(color: muted, fontSize: 12),
        ),
      ),
    ];
  }

  String _recipeDuration(WorkoutRecipe recipe) => recipe.isFree
      ? 'Sin límite de tiempo'
      : '${durationLabel(recipe.seconds)}${recipe.meters > 0 ? ' + ${(recipe.meters / 1000).toStringAsFixed(1)} km' : ' en total'}';

  void _preview(WorkoutRecipe recipe) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheetContext) => SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * .8,
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text(
              recipe.title,
              style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text(_recipeDuration(recipe), style: const TextStyle(color: lime)),
            const SizedBox(height: 12),
            for (final block in recipe.blocks)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  block.kind == BlockKind.run
                      ? Icons.directions_run
                      : Icons.directions_walk,
                  color: block.kind == BlockKind.run ? lime : recoveryBlue,
                ),
                title: Text(block.label),
                trailing: Text(
                  block.meters > 0
                      ? '${(block.meters / 1000).toStringAsFixed(1)} km'
                      : durationLabel(block.seconds),
                ),
              ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: model.trainingActive || model.busy
                  ? null
                  : () {
                      model.selectWorkout(recipe);
                      Navigator.pop(sheetContext);
                      setState(() => tab = 0);
                    },
              child: const Text('Elegir esta sesión'),
            ),
          ],
        ),
      ),
    ),
  );

  List<Widget> _history() => [
    const SectionHeading(
      'Lo que ya has hecho.',
      subtitle: 'Tu esfuerzo, sesión a sesión.',
    ),
    if (model.history.isEmpty)
      _empty(
        Icons.history,
        'Aquí empieza tu historia',
        'Tu primera sesión aparecerá cuando la guardes.',
      ),
    for (final session in model.history)
      Card(
        child: ListTile(
          contentPadding: const EdgeInsets.all(16),
          leading: Icon(
            session.goalReached
                ? Icons.verified
                : session.complete
                ? Icons.directions_run
                : Icons.history,
            color: lime,
          ),
          title: Text(
            session.title,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              '${dateLabel(session.started)}\n${durationLabel(session.seconds)} · ${(session.meters / 1000).toStringAsFixed(2)} km${session.complete ? '' : ' · interrumpida'}',
              style: const TextStyle(color: muted, height: 1.5),
            ),
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute<void>(
              builder: (_) => TrainingDetail(
                session: session,
                onShare: () => model.share(session.file),
                onCsv: () => model.exportCsv(session),
              ),
            ),
          ),
        ),
      ),
    if (model.history.isNotEmpty)
      Padding(
        padding: const EdgeInsets.only(top: 20),
        child: OutlinedButton.icon(
          onPressed: model.trainingActive ? null : model.exportHistory,
          icon: const Icon(Icons.ios_share),
          label: const Text('Exportar todo el historial'),
        ),
      ),
  ];

  List<Widget> _progress() {
    final stats = TrainingStats(model.history, DateTime.now());
    final daily = stats.dailyMeters;
    final max = daily.fold<double>(1, (a, b) => b > a ? b : a);
    return [
      const SectionHeading(
        'Cada sesión suma.',
        subtitle: 'Tu progreso se construye con lo que haces, no con la velocidad de otros.',
      ),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'ESTA SEMANA',
                style: TextStyle(color: lime, letterSpacing: 2, fontSize: 11),
              ),
              const SizedBox(height: 12),
              Text(
                '${(stats.thisWeek.fold<double>(0, (sum, s) => sum + s.meters) / 1000).toStringAsFixed(2)} km',
                style: const TextStyle(
                  fontSize: 44,
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(
                '${stats.thisWeek.length} ${stats.thisWeek.length == 1 ? 'sesión' : 'sesiones'} · ${durationLabel(stats.thisWeek.fold<int>(0, (sum, s) => sum + s.seconds))} de actividad',
                style: const TextStyle(color: muted),
              ),
            ],
          ),
        ),
      ),
      const SectionHeading(
        'Últimos 7 días',
        subtitle: 'Distancia registrada cada día',
      ),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (var i = 0; i < daily.length; i++)
                Expanded(
                  child: Semantics(
                    label:
                        '${stats.days[i].day}/${stats.days[i].month}: ${(daily[i] / 1000).toStringAsFixed(2)} kilómetros',
                    child: Column(
                      children: [
                        Text(
                          (daily[i] / 1000).toStringAsFixed(2),
                          style: const TextStyle(fontSize: 10, color: muted),
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          height: 120,
                          child: Align(
                            alignment: Alignment.bottomCenter,
                            child: Container(
                              width: 18,
                              height: daily[i] == 0 ? 3 : 120 * daily[i] / max,
                              decoration: BoxDecoration(
                                color: i == 6
                                    ? lime
                                    : recoveryBlue.withValues(alpha: .6),
                                borderRadius: BorderRadius.circular(6),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '${stats.days[i].day}',
                          style: const TextStyle(color: muted),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
      const SectionHeading('Desde el primer día'),
      TrainingMetrics(
        speed: stats.averageKmh,
        seconds: stats.seconds,
        meters: stats.meters,
      ),
      Text(
        '${model.history.length} ${model.history.length == 1 ? 'sesión' : 'sesiones'} · salida más larga: ${(stats.longestMeters / 1000).toStringAsFixed(2)} km',
        style: const TextStyle(color: muted),
      ),
      const SizedBox(height: 12),
      const Text(
        'El ritmo medio incluye las recuperaciones y excluye las pausas manuales. Las sesiones interrumpidas también cuentan.',
        style: TextStyle(color: muted, fontSize: 12),
      ),
    ];
  }

  Widget _empty(IconData icon, String title, String subtitle) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 40),
    child: Column(
      children: [
        Icon(icon, size: 60, color: muted),
        const SizedBox(height: 20),
        Text(
          title,
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Text(
          subtitle,
          textAlign: TextAlign.center,
          style: const TextStyle(color: muted),
        ),
      ],
    ),
  );

  void _settings() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => ListenableBuilder(
        listenable: model,
        builder: (context, _) => SafeArea(
          child: SizedBox(
            height: MediaQuery.sizeOf(context).height * .8,
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                const SectionHeading('A tu manera'),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Avisos de voz'),
                  subtitle: const Text(
                    'Usa la voz y el idioma del móvil. Al desactivar, sonarán pitidos.',
                  ),
                  value: model.preferences.voice,
                  onChanged: (value) => model.setPreference('voice', value),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Vibración'),
                  value: model.preferences.haptics,
                  onChanged: (value) => model.setPreference('haptics', value),
                ),
                const SectionHeading('Tus datos son tuyos'),
                const Text(
                  'Sin registro y sin subidas automáticas. Todo se guarda en este móvil. Exporta una copia antes de cambiar de teléfono o desinstalar.',
                ),
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: model.trainingActive ? null : model.exportHistory,
                  child: const Text('Exportar copia JSON'),
                ),
                const Text(
                  'La copia incluye las sesiones completas. Al restaurar se añaden las nuevas y se omiten los duplicados; no se borran las que ya tienes.',
                  style: TextStyle(color: muted, fontSize: 12),
                ),
                OutlinedButton.icon(
                  onPressed: model.trainingActive
                      ? null
                      : () async {
                          final count = await model.restoreHistory();
                          if (context.mounted && count != null) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('$count sesiones restauradas'),
                              ),
                            );
                          }
                        },
                  icon: const Icon(Icons.file_open_outlined),
                  label: const Text('Restaurar copia JSON'),
                ),
                const SizedBox(height: 20),
                const Text(
                  'SimpleRunning · 1.3.2\nHecha para correr. Sin cuentas. Sin ruido.',
                  style: TextStyle(color: muted),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
