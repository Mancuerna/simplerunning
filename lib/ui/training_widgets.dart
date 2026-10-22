import 'package:flutter/material.dart';

import '../data/training_store.dart';
import '../domain/kilometer_splits.dart';
import 'app_theme.dart';

String durationLabel(int seconds) =>
    '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
String paceLabel(double? speed) =>
    speed == null || !speed.isFinite || speed <= 0
    ? '—'
    : durationLabel((3600 / speed).round());
String dateLabel(DateTime date) {
  final d = date.toLocal();
  return '${d.day}/${d.month}/${d.year} · ${d.hour}:${d.minute.toString().padLeft(2, '0')}';
}

class TrainingMetrics extends StatelessWidget {
  const TrainingMetrics({
    super.key,
    required this.speed,
    required this.seconds,
    required this.meters,
    this.average = false,
  });
  final double? speed;
  final int seconds;
  final double meters;
  final bool average;
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: LayoutBuilder(
        builder: (context, constraints) => Wrap(
          spacing: 16,
          runSpacing: 24,
          children: [
            for (final metric in [
              (
                speed?.toStringAsFixed(1) ?? '—',
                average ? 'VELOCIDAD MEDIA · KM/H' : 'VELOCIDAD ACTUAL · KM/H',
              ),
              (
                paceLabel(speed),
                average ? 'RITMO MEDIO · MIN/KM' : 'RITMO ACTUAL · MIN/KM',
              ),
              (durationLabel(seconds), 'TIEMPO ACTIVO'),
              ((meters / 1000).toStringAsFixed(2), 'KILÓMETROS'),
            ])
              SizedBox(
                width: (constraints.maxWidth - 16) / 2,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        metric.$1,
                        style: const TextStyle(
                          fontSize: 34,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -1,
                        ),
                      ),
                    ),
                    Text(
                      metric.$2,
                      style: const TextStyle(
                        color: muted,
                        fontSize: 10,
                        letterSpacing: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    ),
  );
}

class PaceHelp extends StatelessWidget {
  const PaceHelp({super.key});

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.centerLeft,
    child: TextButton.icon(
      icon: const Icon(Icons.help_outline, size: 18),
      label: const Text('¿Qué significa min/km?'),
      onPressed: () => showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        builder: (context) => const SafeArea(
          child: SingleChildScrollView(
            padding: EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Ritmo: tiempo por kilómetro',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
                ),
                SizedBox(height: 16),
                Text(
                  '6:00 min/km significa que tardas 6 minutos en recorrer 1 km. Cuanto menor es el tiempo, más rápido corres.',
                ),
                SizedBox(height: 16),
                Text(
                  '5:00 min/km = 12 km/h\n6:00 min/km = 10 km/h\n7:30 min/km = 8 km/h',
                ),
                SizedBox(height: 16),
                Text(
                  'El ritmo actual refleja la velocidad de la cinta ahora. El ritmo medio usa la distancia y el tiempo activo de toda la sesión, incluidas las recuperaciones y sin las pausas manuales.',
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class KilometerBreakdown extends StatelessWidget {
  const KilometerBreakdown({
    super.key,
    required this.splits,
    this.live = false,
  });
  final KilometerSplits splits;
  final bool live;

  @override
  Widget build(BuildContext context) {
    final best = splits.fastest;
    final rows = [
      ...splits.completed,
      if (splits.partial != null) splits.partial!,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeading(
          'Kilómetro a kilómetro',
          subtitle: live
              ? 'Parciales de esta sesión'
              : 'Tiempo, ritmo y velocidad de cada parcial',
        ),
        if (live) ...[
          Text(
            'Kilómetro ${splits.currentNumber} en curso',
            style: const TextStyle(color: lime, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          LinearProgressIndicator(
            value: (splits.currentMeters / 1000).clamp(0, 1),
            borderRadius: BorderRadius.circular(8),
          ),
          const SizedBox(height: 8),
          Text(
            '${splits.currentMeters.round()} / 1000 m · ${durationLabel(splits.currentSeconds.round())}',
          ),
        ],
        if (best != null)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Kilómetro más rápido',
                    style: TextStyle(color: lime, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Km ${best.number} · ${paceLabel(best.speedKmh)} min/km · ${best.speedKmh!.toStringAsFixed(1)} km/h',
                  ),
                  const Text(
                    'Mejor parcial completo de 1 km',
                    style: TextStyle(color: muted, fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
        if (splits.completed.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text(
              'Al completar 1 km aparecerá tu primer parcial y tu kilómetro más rápido.',
              style: TextStyle(color: muted),
            ),
          ),
        if (rows.isNotEmpty)
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              dataRowMinHeight: 64,
              dataRowMaxHeight: 64 * MediaQuery.textScalerOf(context).scale(1),
              horizontalMargin: 8,
              columnSpacing: 18,
              columns: const [
                DataColumn(label: Text('Km')),
                DataColumn(label: Text('Tiempo')),
                DataColumn(label: Text('min/km')),
                DataColumn(label: Text('km/h')),
              ],
              rows: [
                for (final split in rows)
                  DataRow(
                    color: split == best
                        ? const WidgetStatePropertyAll(Color(0xFF283C2E))
                        : null,
                    cells: [
                      DataCell(
                        Text(
                          split.complete
                              ? '${split.number}'
                              : '${split.number} · parcial\n${(split.meters / 1000).toStringAsFixed(2)} km',
                        ),
                      ),
                      DataCell(
                        Text(
                          split.reliable
                              ? durationLabel(split.seconds.round())
                              : '—',
                        ),
                      ),
                      DataCell(Text(paceLabel(split.speedKmh))),
                      DataCell(Text(split.speedKmh?.toStringAsFixed(1) ?? '—')),
                    ],
                  ),
              ],
            ),
          ),
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 12),
          child: Text(
            'Parciales estimados con los datos de distancia de la cinta. Incluyen recuperaciones y excluyen pausas manuales. El tramo final incompleto no cuenta como mejor kilómetro.',
            style: TextStyle(color: muted, fontSize: 12),
          ),
        ),
        if (splits.hasGaps)
          const Text(
            'Hay tramos sin muestras suficientes. No se usan para elegir el kilómetro más rápido.',
            style: TextStyle(color: Colors.orangeAccent),
          ),
      ],
    );
  }
}

class TrainingDetail extends StatelessWidget {
  const TrainingDetail({
    super.key,
    required this.session,
    required this.onShare,
    this.onCsv,
  });
  final TrainingSession session;
  final VoidCallback onShare;
  final VoidCallback? onCsv;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Tu sesión'),
      actions: [
        if (onCsv != null)
          IconButton(
            onPressed: onCsv,
            tooltip: 'Exportar CSV',
            icon: const Icon(Icons.table_chart_outlined),
          ),
        IconButton(
          onPressed: onShare,
          icon: const Icon(Icons.share),
          tooltip: 'Exportar sesión',
        ),
      ],
    ),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          session.title,
          style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        Text(dateLabel(session.started), style: const TextStyle(color: muted)),
        if (session.goalReached)
          const Chip(
            avatar: Icon(Icons.verified, color: lime),
            label: Text('Objetivo completado'),
          ),
        if (session.recipeId != 'free' &&
            session.recipeId != 'intervals' &&
            !session.goalReached)
          const Text(
            'Objetivo pendiente · puedes repetir esta sesión',
            style: TextStyle(color: muted),
          ),
        if (!session.complete)
          const Text('Sesión interrumpida · datos recuperados'),
        TrainingMetrics(
          speed: session.averageKmh,
          seconds: session.seconds,
          meters: session.meters,
          average: true,
        ),
        const PaceHelp(),
        const Text(
          'Velocidad y ritmo medios sobre el tiempo activo, incluidas recuperaciones y excluidas pausas manuales.',
        ),
        const SizedBox(height: 24),
        KilometerBreakdown(splits: session.kilometerSplits),
        const SizedBox(height: 24),
        Text(
          'Velocidad durante la sesión',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const Text(
          'Los huecos indican falta de datos. Eje horizontal: tiempo; vertical: km/h.',
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 220,
          child: CustomPaint(
            painter: _SpeedChart(
              session,
              Theme.of(context).colorScheme.primary,
            ),
          ),
        ),
        Text('0:00 → ${durationLabel(session.seconds)}'),
        const SizedBox(height: 24),
        Text(
          'Velocidad máxima registrada: ${session.peakKmh.toStringAsFixed(1)} km/h',
          style: const TextStyle(color: lime),
        ),
        if (session.phases.isNotEmpty) ...[
          const SectionHeading(
            'Tus bloques',
            subtitle: 'Distancia y ritmo aproximados: la cinta informa la distancia cada 10 m.',
          ),
          for (final phase in session.phases)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(phase.label),
              subtitle: Text(
                '${durationLabel(phase.seconds)} · ${(phase.meters / 1000).toStringAsFixed(2)} km',
              ),
              trailing: Text('${paceLabel(phase.speed)} /km'),
            ),
        ],
        if (session.events.any((e) => e['type'] == 'pause'))
          Text(
            '${session.events.where((e) => e['type'] == 'pause').length} pausas manuales',
            style: const TextStyle(color: muted),
          ),
        const SizedBox(height: 24),
        const Text(
          'Guardada en este móvil. Exporta la sesión para conservar una copia.',
        ),
      ],
    ),
  );
}

class _SpeedChart extends CustomPainter {
  _SpeedChart(this.session, this.color);
  final TrainingSession session;
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    double maxSpeed = 1;
    for (final sample in session.samples) {
      final speed = sample['speed_kmh'] as num?;
      if (speed != null && speed > maxSpeed) maxSpeed = speed.toDouble();
    }
    final text = TextPainter(
      text: TextSpan(
        text: '${maxSpeed.toStringAsFixed(1)} km/h',
        style: TextStyle(color: color, fontSize: 12),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    text.paint(canvas, Offset.zero);
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    final path = Path();
    bool connected = false;
    int? lastSecond;
    for (final sample in session.samples) {
      final speed = sample['speed_kmh'] as num?;
      final second = (sample['seconds'] as num).toInt();
      if (speed == null) {
        connected = false;
        continue;
      }
      final x =
          second / (session.seconds == 0 ? 1 : session.seconds) * size.width;
      final y = size.height - speed / maxSpeed * (size.height - 24);
      if (connected && lastSecond != null && second - lastSecond <= 2) {
        path.lineTo(x, y);
      } else {
        path.moveTo(x, y);
      }
      connected = true;
      lastSecond = second;
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _SpeedChart oldDelegate) =>
      oldDelegate.session != session || oldDelegate.color != color;
}
