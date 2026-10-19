import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'data/ble_repository.dart';
import 'data/training_store.dart';
import 'data/app_preferences.dart';
import 'data/audio_coach.dart';
import 'ui/app_theme.dart';
import 'ui/capture_model.dart';
import 'ui/capture_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final directory = await getApplicationDocumentsDirectory();
  final model = CaptureModel(
    BleRepository(FlutterReactiveBle()),
    null,
    training: TrainingStore(Directory(p.join(directory.path, 'trainings'))),
    preferences: AppPreferences(
      File(p.join(directory.path, 'preferences.json')),
    ),
    coach: AudioCoach(),
  );
  model.refreshHistory();
  runApp(
    MaterialApp(
      title: 'SimpleRunning',
      debugShowCheckedModeBanner: false,
      theme: runningTheme,
      home: CaptureScreen(model: model),
    ),
  );
}
