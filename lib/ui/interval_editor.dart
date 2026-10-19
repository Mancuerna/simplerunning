import 'package:flutter/material.dart';

import '../domain/workout.dart';
import 'capture_model.dart';
import 'training_widgets.dart';
import 'app_theme.dart';

class IntervalEditor extends StatefulWidget {
  const IntervalEditor({super.key, required this.model});
  final CaptureModel model;
  @override
  State<IntervalEditor> createState() => _IntervalEditorState();
}

class _IntervalEditorState extends State<IntervalEditor> {
  late int rounds = widget.model.preferences.number('rounds', 4).clamp(1, 30);
  late int run = widget.model.preferences.number('run', 120).clamp(5, 3600);
  late int rest = widget.model.preferences.number('rest', 120).clamp(5, 3600);
  late int warm = widget.model.preferences.number('warm', 300).clamp(0, 1800);
  late int cool = widget.model.preferences.number('cool', 300).clamp(0, 1800);
  @override
  Widget build(BuildContext context) {
    final recipe = WorkoutRecipe.intervals(
      rounds: rounds,
      run: run,
      recovery: rest,
      warmup: warm,
      cooldown: cool,
    );
    return Scaffold(
      appBar: AppBar(title: const Text('Tus intervalos')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text(
            'CAMBIA DE RITMO',
            style: TextStyle(
              color: lime,
              letterSpacing: 2,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SectionHeading(
            'Corre. Recupera. Repite.',
            subtitle:
                'Tú eliges la intensidad. La app te avisa de cada cambio.',
          ),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    durationLabel(recipe.seconds),
                    style: const TextStyle(
                      fontSize: 44,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    '$rounds tandas de carrera + $rounds recuperaciones',
                    style: const TextStyle(color: muted),
                  ),
                ],
              ),
            ),
          ),
          _stepper(
            'Tandas',
            '$rounds',
            () => rounds > 1 ? setState(() => rounds--) : null,
            () => rounds < 30 ? setState(() => rounds++) : null,
          ),
          _stepper(
            'Carrera',
            durationLabel(run),
            () => setState(() => run = (run - 15).clamp(5, 3600)),
            () => setState(() => run = (run + 15).clamp(5, 3600)),
          ),
          _stepper(
            'Recuperación',
            durationLabel(rest),
            () => setState(() => rest = (rest - 15).clamp(5, 3600)),
            () => setState(() => rest = (rest + 15).clamp(5, 3600)),
          ),
          _stepper(
            'Calentamiento',
            durationLabel(warm),
            () => setState(() => warm = (warm - 60).clamp(0, 1800)),
            () => setState(() => warm = (warm + 60).clamp(0, 1800)),
          ),
          _stepper(
            'Vuelta a la calma',
            durationLabel(cool),
            () => setState(() => cool = (cool - 60).clamp(0, 1800)),
            () => setState(() => cool = (cool + 60).clamp(0, 1800)),
          ),
          const SizedBox(height: 20),
          const Text(
            'Recupera andando o parado. La intensidad no se controla desde la app.',
            style: TextStyle(color: muted),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: () {
              for (final entry in {
                'rounds': rounds,
                'run': run,
                'rest': rest,
                'warm': warm,
                'cool': cool,
              }.entries) {
                widget.model.setPreference(entry.key, entry.value);
              }
              widget.model.selectWorkout(recipe);
              Navigator.pop(context);
            },
            icon: const Icon(Icons.check),
            label: const Text('Usar este entrenamiento'),
          ),
        ],
      ),
    );
  }

  Widget _stepper(
    String label,
    String value,
    VoidCallback minus,
    VoidCallback plus,
  ) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 9),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: muted)),
        Row(
          children: [
            Expanded(
              child: Text(
                value,
                style: const TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            IconButton.filledTonal(
              onPressed: minus,
              tooltip: 'Reducir $label',
              icon: const Icon(Icons.remove),
            ),
            const SizedBox(width: 12),
            IconButton.filledTonal(
              onPressed: plus,
              tooltip: 'Aumentar $label',
              icon: const Icon(Icons.add),
            ),
          ],
        ),
      ],
    ),
  );
}
