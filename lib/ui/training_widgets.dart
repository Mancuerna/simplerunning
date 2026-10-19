import 'package:flutter/material.dart';

import '../data/training_store.dart';
import 'app_theme.dart';

String durationLabel(int seconds) =>
    '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
String paceLabel(double? speed) =>
    speed == null || speed <= 0 ? '—' : durationLabel((3600 / speed).round());
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
  });
  final double? speed;
  final int seconds;
  final double meters;
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
              (speed?.toStringAsFixed(1) ?? '—', 'KM/H'),
              (paceLabel(speed), 'MIN/KM'),
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
        ),
        const Text(
          'Velocidad y ritmo medios sobre el tiempo activo, incluidas recuperaciones y excluidas pausas manuales.',
        ),
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
