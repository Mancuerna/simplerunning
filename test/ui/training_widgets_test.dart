import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simplerunning/domain/kilometer_splits.dart';
import 'package:simplerunning/ui/app_theme.dart';
import 'package:simplerunning/ui/training_widgets.dart';

import '../domain/kilometer_splits_test.dart' show sampleRun;

void main() {
  test('pace expresses minutes per kilometer', () {
    expect(paceLabel(10), '6:00');
    expect(paceLabel(12), '5:00');
    expect(paceLabel(8), '7:30');
    expect(paceLabel(0), '—');
    expect(paceLabel(null), '—');
  });

  testWidgets(
    'kilometer table and help work on a narrow phone with large text',
    (tester) async {
      tester.view.physicalSize = const Size(360, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          theme: runningTheme,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: Scaffold(
            body: SingleChildScrollView(
              child: Column(
                children: [
                  const PaceHelp(),
                  KilometerBreakdown(
                    splits: KilometerSplits.fromSamples(sampleRun()),
                    live: true,
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      expect(find.text('Kilómetro 3 en curso'), findsOneWidget);
      expect(find.text('Km 2 · 5:00 min/km · 12.0 km/h'), findsOneWidget);
      expect(find.text('3 · parcial\n0.25 km'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('¿Qué significa min/km?'));
      await tester.pumpAndSettle();
      expect(find.text('Ritmo: tiempo por kilómetro'), findsOneWidget);
      expect(find.textContaining('6 minutos'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
