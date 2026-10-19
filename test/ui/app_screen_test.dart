import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simplerunning/data/capture_log.dart';
import 'package:simplerunning/data/training_store.dart';
import 'package:simplerunning/domain/workout.dart';
import 'package:simplerunning/ui/app_theme.dart';
import 'package:simplerunning/ui/capture_model.dart';
import 'package:simplerunning/ui/capture_screen.dart';
import 'package:simplerunning/ui/interval_editor.dart';

import 'capture_model_test.dart' show FakeBle;

void main() {
  late Directory dir;
  late CaptureModel model;
  setUp(() {
    dir = Directory.systemTemp.createTempSync('screen_test_');
    model = CaptureModel(
      FakeBle(),
      CaptureLog(Directory('${dir.path}/captures')),
      training: TrainingStore(Directory('${dir.path}/sessions')),
      keepAwake: (_) async {},
    );
  });
  tearDown(() {
    model.training?.finish(complete: false);
    model.dispose();
    dir.deleteSync(recursive: true);
  });

  testWidgets(
    'navigation, empty history and plan selection work on a narrow phone',
    (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          theme: runningTheme,
          home: CaptureScreen(model: model),
        ),
      );
      expect(find.text('TU PRÓXIMA SESIÓN'), findsOneWidget);
      await tester.tap(find.text('Historial'));
      await tester.pumpAndSettle();
      expect(find.text('Aquí empieza tu historia'), findsOneWidget);
      await tester.tap(find.text('Planes'));
      await tester.pumpAndSettle();
      await Scrollable.ensureVisible(
        tester.element(find.text('Semana 1').first),
        alignment: .3,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Semana 1').first);
      await tester.pumpAndSettle();
      await Scrollable.ensureVisible(
        tester.element(find.text('Día 1')),
        alignment: .3,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Día 1').first);
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Elegir esta sesión'),
        300,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.tap(find.text('Elegir esta sesión'));
      await tester.pumpAndSettle();
      expect(model.selectedWorkout.id, '5k-w1-d1');
      expect(find.text('TU PRÓXIMA SESIÓN'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('interval editor updates rounds and selects recipe', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: runningTheme,
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => IntervalEditor(model: model),
                ),
              ),
              child: const Text('edit'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('edit'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Aumentar Tandas'));
    await tester.pump();
    await tester.scrollUntilVisible(find.text('Usar este entrenamiento'), 300);
    await tester.tap(find.text('Usar este entrenamiento'));
    await tester.pumpAndSettle();
    expect(
      model.selectedWorkout.blocks.where((b) => b.kind == BlockKind.run),
      hasLength(5),
    );
    expect(model.preferences.number('rounds', 0), 5);
    expect(tester.takeException(), isNull);
  });

  testWidgets('active session pause and countdown render with large text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    model.training!.start(0);
    model.runner = WorkoutRunner(WorkoutRecipe.intervals());
    await tester.pumpWidget(
      MaterialApp(
        theme: runningTheme,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(1.4)),
          child: child!,
        ),
        home: CaptureScreen(model: model),
      ),
    );
    await tester.scrollUntilVisible(find.text('Pausar'), 250);
    await tester.tap(find.text('Pausar'));
    await tester.pumpAndSettle();
    expect(model.paused, isTrue);
    expect(find.text('Continuar'), findsOneWidget);
    await tester.tap(find.text('Continuar'));
    await tester.pumpAndSettle();
    expect(model.paused, isFalse);
    expect(tester.takeException(), isNull);
  });
}
