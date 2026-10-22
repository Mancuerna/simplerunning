import 'dart:async';
import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:share_plus/share_plus.dart';

import '../data/background_recording.dart';

import '../data/ble_repository.dart';
import '../data/capture_log.dart';
import '../data/fitshow_diagnostics.dart';
import '../data/training_store.dart';
import '../data/app_preferences.dart';
import '../data/audio_coach.dart';
import '../data/file_exchange.dart';
import '../domain/workout.dart';

class CaptureModel extends ChangeNotifier {
  CaptureModel(
    this.ble,
    this.log, {
    Future<void> Function(bool)? keepAwake,
    this.training,
    AppPreferences? preferences,
    this.coach,
  }) : preferences = preferences ?? AppPreferences(null),
       _keepAwake = keepAwake ?? BackgroundRecording.setEnabled;
  final TrainingStore? training;
  final AppPreferences preferences;
  final AudioCoach? coach;
  WorkoutRecipe selectedWorkout = WorkoutRecipe.free;
  WorkoutRunner? runner;
  bool get paused => training?.paused ?? false;
  String? lastSavedMessage;

  void selectWorkout(WorkoutRecipe recipe) {
    if (trainingActive || busy) return;
    selectedWorkout = recipe;
    notifyListeners();
  }

  Future<void> announce(String text, {bool countdown = false}) async {
    try {
      await coach?.cue(
        text,
        voice: preferences.voice,
        haptics: preferences.haptics,
        countdown: countdown,
      );
    } catch (_) {
      /* Audio is optional; keep the training clock running. */
    }
  }

  void setPreference(String key, Object value) {
    try {
      preferences.set(key, value);
      if (key == 'voice' && value == false) unawaited(coach?.stop());
    } catch (_) {
      error = 'No se pudo guardar este ajuste.';
    }
    notifyListeners();
  }

  void togglePause() {
    if (!trainingActive || busy) return;
    try {
      if (paused) {
        training!.resume();
        unawaited(
          announce('Continuamos. ${runner?.current?.label ?? 'A tu ritmo'}'),
        );
      } else {
        training!.pause();
        unawaited(announce('Entrenamiento en pausa'));
      }
    } catch (_) {
      error = 'No se pudo guardar la pausa.';
      unawaited(stop());
    }
    notifyListeners();
  }

  void skipBlock() {
    if (!trainingActive || paused || runner?.current == null || busy) return;
    try {
      training!.sample(liveSpeed);
      training!.event('skip');
      runner!.skip(training!.seconds, training!.meters);
      _phaseChanged();
    } catch (_) {
      error = 'No se pudo guardar el cambio de bloque.';
      unawaited(stop());
    }
    notifyListeners();
  }

  void extendBlock() {
    if (!trainingActive || runner?.current == null || busy) return;
    try {
      runner!.extend();
      training!.event('extend');
      unawaited(announce('Treinta segundos más'));
    } catch (_) {
      error = 'No se pudo guardar el cambio.';
      unawaited(stop());
    }
    notifyListeners();
  }

  void _phaseChanged() {
    if (runner!.finished) {
      unawaited(finishTraining());
    } else {
      training!.setPhase(runner!);
      training!.sample(liveSpeed);
      unawaited(announce(runner!.current!.label));
    }
  }

  Future<int?> restoreHistory() async {
    if (trainingActive || training == null) return null;
    try {
      final contents = await FileExchange().pickBackup();
      if (contents == null) return null;
      final count = training!.importBackup(contents);
      refreshHistory();
      return count;
    } catch (_) {
      error = 'La copia no es válida o no se pudo leer. Las sesiones existentes se conservan.';
      notifyListeners();
      return null;
    }
  }

  Future<void> exportHistory() async {
    if (training == null) return;
    try {
      await share(training!.exportAll());
    } catch (_) {
      error = 'No se pudo exportar el historial.';
      notifyListeners();
    }
  }

  Future<void> exportCsv(TrainingSession session) async {
    if (training == null) return;
    try {
      await share(training!.exportCsv(session));
    } catch (_) {
      error = 'No se pudo exportar la sesión.';
      notifyListeners();
    }
  }

  List<TrainingSession> history = [];
  Timer? _trainingTimer;
  double? speedKmh;
  DateTime? _speedAt;
  bool get speedFresh =>
      _speedAt != null &&
      DateTime.now().difference(_speedAt!) < const Duration(seconds: 5);
  double? get liveSpeed => speedFresh ? speedKmh : null;
  bool get trainingActive => training?.recording ?? false;
  void refreshHistory() {
    try {
      history = training?.load() ?? [];
    } catch (_) {
      error = 'No se pudo leer el historial.';
    }
    notifyListeners();
  }

  // A quiet console may only send status after initializeFitShow.
  // Starting must depend on its channels, not an unsolicited first packet.
  bool get canStartTraining =>
      active &&
      !busy &&
      _discovered &&
      _hasQueryChannel &&
      _hasStatusChannel &&
      !trainingActive;

  Future<void> startTraining() async {
    if (!canStartTraining || training == null) return;
    busy = true;
    notifyListeners();
    final generation = _generation;
    try {
      // Wait for the current diagnostic transaction before initializing.
      while (querying && active && generation == _generation) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      if (!active || generation != _generation) return;
      await ble.initializeFitShow(_deviceId!);
      if (!active || generation != _generation) return;
      _record('training_initialized');
      lastSavedMessage = null;
      runner = WorkoutRunner(selectedWorkout);
      training!.start(null, recipe: selectedWorkout);
      if (runner!.current != null) training!.setPhase(runner!);
      unawaited(
        announce(
          runner!.current?.label ?? 'Entrenamiento iniciado. A tu ritmo',
        ),
      );
      _trainingTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        try {
          if (training!.paused) return;
          training!.sample(liveSpeed);
          if (runner!.update(training!.seconds, training!.meters)) {
            _phaseChanged();
          } else if (runner!.current != null && runner!.current!.seconds > 0) {
            final remaining = runner!.remaining(training!.seconds);
            if (remaining > 0 && remaining <= 3) {
              unawaited(announce('$remaining', countdown: true));
            }
          }
        } catch (_) {
          error = 'No se pudo guardar el entrenamiento.';
          unawaited(stop());
        }
        notifyListeners();
      });
      status = '${selectedWorkout.title} · en marcha';
    } catch (_) {
      error = 'No se pudo iniciar el entrenamiento. Vuelve a conectar.';
      if (active && generation == _generation) await stop();
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> finishTraining() async {
    if (!trainingActive || busy) return;
    busy = true;
    notifyListeners();
    _trainingTimer?.cancel();
    try {
      final reached = runner != null && runner!.finished && !runner!.skipped;
      training!.finish(complete: true, goalReached: reached);
      lastSavedMessage = reached
          ? 'Objetivo completado. Sesión guardada.'
          : 'Sesión guardada. Cada paso cuenta.';
      unawaited(
        announce(reached ? 'Entrenamiento completado' : 'Sesión guardada'),
      );
    } catch (_) {
      error = 'Error al guardar la sesión; los datos anteriores se conservan.';
    }
    refreshHistory();
    // Saving locally never depends on a console acknowledgment.
    try {
      while (querying && active) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      if (active) await ble.sendFitShow(_deviceId!, fitShowFrame([0x53, 3]));
    } catch (_) {
      error = 'Sesión guardada; no se pudo enviar la parada a la consola.';
    }
    await stop();
  }

  final Future<void> Function(bool) _keepAwake;
  Future<void>? _startingKeepAwake;
  bool _stopping = false;
  final BleRepository ble;
  // Optional developer instrumentation; the installed app does not supply it.
  final CaptureLog? log;
  final Map<String, DiscoveredDevice> _devices = {};
  List<DiscoveredDevice> get devices => List.unmodifiable(_devices.values);
  StreamSubscription<DiscoveredDevice>? _scan;
  StreamSubscription<ConnectionStateUpdate>? _connection;
  final List<StreamSubscription<List<int>>> _notifications = [];
  Timer? _scanTimer;
  bool scanning = false;
  bool active = false;
  bool busy = false;
  int packets = 0;
  String? _deviceId;
  bool _hasQueryChannel = false;
  bool _hasStatusChannel = false;
  bool _receivedFitShowStatus = false;
  bool _discovered = false;
  bool querying = false;
  Timer? _pollTimer;
  int _pollIndex = 0;
  bool _pollFailed = false;
  int _writeFailures = 0;
  FitShowQuery? _pendingQuery;
  Completer<bool>? _pendingReply;
  FitShowWorkout? workout;
  DateTime? workoutReceivedAt;
  bool get workoutStale =>
      workoutReceivedAt != null &&
      DateTime.now().difference(workoutReceivedAt!) >
          const Duration(seconds: 10);
  bool get polling => _pollTimer != null;
  int matchingReplies = 0;
  int unansweredQueries = 0;
  String? queryStatus;
  double? reportedSpeed;
  bool get canQuery =>
      active &&
      !busy &&
      !querying &&
      _discovered &&
      _hasQueryChannel &&
      _receivedFitShowStatus;
  int _generation = 0;
  String status = 'Busca la cinta para empezar';
  String? error;

  Future<void> scan() async {
    if (busy || active || scanning || _stopping) return;
    busy = true;
    error = null;
    notifyListeners();
    try {
      final sdk = (await DeviceInfoPlugin().androidInfo).version.sdkInt;
      final permissions =
          await (sdk >= 31
                  ? [Permission.bluetoothScan, Permission.bluetoothConnect]
                  : [Permission.locationWhenInUse])
              .request();
      if (permissions.values.any((p) => !p.isGranted)) {
        throw StateError(
          'Concede los permisos Bluetooth en los ajustes de la app.',
        );
      }
      if (ble.client.status != BleStatus.ready) {
        await ble.client.statusStream
            .firstWhere((s) => s == BleStatus.ready)
            .timeout(const Duration(seconds: 5));
      }
      _devices.clear();
      scanning = true;
      status = 'Buscando durante 15 segundos…';
      _scan = ble.scan().listen(
        (device) {
          _devices[device.id] = device;
          notifyListeners();
        },
        onError: (Object e) {
          error = 'No se pudo buscar. Comprueba Bluetooth y ubicación: $e';
          unawaited(stopScan());
        },
      );
      _scanTimer = Timer(
        const Duration(seconds: 15),
        () => unawaited(stopScan()),
      );
    } catch (e) {
      error =
          'No se pudo buscar. Comprueba Bluetooth, permisos y ubicación: $e';
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> stopScan() async {
    _scanTimer?.cancel();
    await _scan?.cancel();
    _scan = null;
    scanning = false;
    if (!active) status = 'Selecciona la cinta o vuelve a buscar';
    notifyListeners();
  }

  void _record(String type, [Map<String, Object?> data = const {}]) {
    try {
      log?.add(type, data);
    } catch (e) {
      error = 'No se pudo guardar la captura: $e';
      unawaited(stop());
    }
    notifyListeners();
  }

  Future<void> connect(DiscoveredDevice device) async {
    if (active || busy || _stopping) return;
    busy = true;
    error = null;
    notifyListeners();
    try {
      await stopScan();
      log?.start();
      packets = 0;
      _deviceId = device.id;
      _hasQueryChannel = false;
      _hasStatusChannel = false;
      _receivedFitShowStatus = false;
      _discovered = false;
      querying = false;
      _pollTimer?.cancel();
      _pollTimer = null;
      _pollFailed = false;
      _pollIndex = 0;
      _writeFailures = 0;
      matchingReplies = 0;
      unansweredQueries = 0;
      workout = null;
      workoutReceivedAt = null;
      queryStatus = null;
      reportedSpeed = null;
      speedKmh = null;
      _speedAt = null;
      active = true;
      final generation = ++_generation;
      _startingKeepAwake = _keepAwake(true);
      await _startingKeepAwake;
      if (!active || generation != _generation) return;
      // Identifiers stay in memory. Raw payloads may still contain identifiers.
      _record('advertisement', {
        'rssi': device.rssi,
        'services': device.serviceUuids.map((s) => s.toString()).toList(),
        'manufacturer_hex': _hex(device.manufacturerData),
        'service_data': {
          for (final e in device.serviceData.entries)
            e.key.toString(): _hex(e.value),
        },
      });
      status = 'Conectando…';
      _connection = ble
          .connect(device.id)
          .listen(
            (update) {
              if (generation != _generation || !active) return;
              _record('connection', {'state': update.connectionState.name});
              if (update.connectionState == DeviceConnectionState.connected) {
                status = 'Descubriendo servicios…';
                unawaited(_discover(device.id, generation));
              } else if (update.connectionState ==
                  DeviceConnectionState.disconnected) {
                error = 'La cinta se ha desconectado. El entrenamiento queda guardado.';
                unawaited(stop());
              }
            },
            onError: (Object e) {
              if (generation != _generation) return;
              error = 'Error de conexión: $e';
              _record('connection_error');
              unawaited(stop());
            },
          );
    } catch (e) {
      error = 'No se pudo conectar con la cinta: $e';
      await stop();
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  static String _hex(List<int> bytes) =>
      bytes.map((v) => v.toRadixString(16).padLeft(2, '0')).join();

  Future<void> _discover(String id, int generation) async {
    bool current() => active && generation == _generation;
    try {
      final services = await ble
          .discover(id)
          .timeout(const Duration(seconds: 20));
      if (!current()) return;
      for (final service in services) {
        _record('service', {'service': service.id.toString()});
        for (final c in service.characteristics) {
          if (!current()) return;
          final context = <String, Object?>{
            'service': c.service.id.toString(),
            'characteristic': c.id.toString(),
          };
          _record('characteristic', {
            ...context,
            'read': c.isReadable,
            'notify': c.isNotifiable,
            'indicate': c.isIndicatable,
            'write': c.isWritableWithResponse,
            'write_without_response': c.isWritableWithoutResponse,
          });
          if (c.service.id == Uuid.parse('fff0').expanded &&
              c.id == Uuid.parse('fff2').expanded &&
              c.isWritableWithoutResponse) {
            _hasQueryChannel = true;
          }
          final isTrainingChannel =
              c.service.id == Uuid.parse('fff0').expanded &&
              c.id == Uuid.parse('fff1').expanded;
          if ((c.isNotifiable || c.isIndicatable) &&
              (log != null || isTrainingChannel)) {
            if (isTrainingChannel) _hasStatusChannel = true;
            _record('subscribe_requested', context);
            _notifications.add(
              ble
                  .subscribe(id, c)
                  .listen(
                    (bytes) {
                      if (!current()) return;
                      packets++;
                      if (c.service.id == Uuid.parse('fff0').expanded &&
                          c.id == Uuid.parse('fff1').expanded) {
                        if (isFitShowStatus(bytes)) {
                          _receivedFitShowStatus = true;
                        }
                        final state = FitShowStatus.parse(bytes);
                        if (state != null) {
                          speedKmh = state.speedKmh;
                          _speedAt = DateTime.now();
                        }
                        final sample = FitShowWorkout.parse(bytes);
                        if (sample != null) {
                          workout = sample;
                          training?.distance(sample.distanceRaw);
                          workoutReceivedAt = DateTime.now();
                        }
                        final pending = _pendingReply;
                        if (pending != null &&
                            !pending.isCompleted &&
                            _pendingQuery != null &&
                            matchesFitShowQuery(_pendingQuery!, bytes)) {
                          pending.complete(true);
                        }
                      }
                      if (c.service.id == Uuid.parse('1826').expanded &&
                          c.id == Uuid.parse('2acd').expanded) {
                        final speed = treadmillSpeed(bytes);
                        if (speed != null) reportedSpeed = speed;
                      }
                      _record('notification', {
                        ...context,
                        'hex': _hex(bytes),
                        'length': bytes.length,
                      });
                      _startPolling();
                    },
                    onError: (Object e) {
                      if (!current()) return;
                      // Plugin exception strings can contain a device address.
                      _record('subscribe_error', context);
                      error = 'No se reciben datos de la cinta. Prueba a volver a conectar.';
                      notifyListeners();
                    },
                  ),
            );
          }
          if (c.isReadable && log != null) {
            try {
              final bytes = await ble.read(id, c);
              if (!current()) return;
              packets++;
              _record('read', {
                ...context,
                'hex': _hex(bytes),
                'length': bytes.length,
              });
            } catch (_) {
              if (!current()) return;
              _record('read_error', context);
            }
          }
        }
      }
      if (current()) {
        _discovered = true;
        if (_hasQueryChannel && _hasStatusChannel) {
          status = 'Cinta conectada · lista para entrenar';
        } else {
          status = 'Cinta conectada · no compatible';
          error =
              'La cinta no ofrece los canales FitShow necesarios. '
              'Prueba a conectar con otra entrada Bluetooth de la cinta.';
        }
        _record('discovery_complete');
        _startPolling();
      }
    } catch (_) {
      if (!current()) return;
      error = 'Falló el descubrimiento de servicios. Puedes volver a conectar.';
      _record('discovery_error');
      await stop();
    }
  }

  void _startPolling() {
    if (!canQuery || _pollTimer != null || _pollFailed) return;
    _record('polling_started');
    if (!active) return;
    _pollTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (canQuery) unawaited(queryData());
      notifyListeners();
    });
  }

  void retryPolling() {
    _pollFailed = false;
    _writeFailures = 0;
    _startPolling();
  }

  Future<void> queryData() async {
    if (!canQuery) return;
    const queries = [
      FitShowQuery.workout,
      FitShowQuery.status,
      FitShowQuery.status,
    ];
    final query = queries[_pollIndex++ % queries.length];
    final id = _deviceId!;
    final generation = _generation;
    bool current() => active && generation == _generation;
    querying = true;
    final reply = Completer<bool>();
    _pendingReply = reply;
    _pendingQuery = query;
    queryStatus = 'Consultas automáticas activas';
    final context = <String, Object?>{
      'service': '0000fff0-0000-1000-8000-00805f9b34fb',
      'characteristic': '0000fff2-0000-1000-8000-00805f9b34fb',
      'query': query.name,
      'hex': _hex(query.bytes),
    };
    _record('diagnostic_write_requested', context);
    try {
      if (!current()) return;
      try {
        await ble.queryFitShow(id, query);
      } catch (_) {
        if (!current()) return;
        _writeFailures++;
        _record('diagnostic_write_error', context);
        if (_writeFailures >= 3) {
          _pollFailed = true;
          _pollTimer?.cancel();
          _pollTimer = null;
          queryStatus =
              'Consultas detenidas tras tres errores. Puedes reintentarlas.';
          _record('polling_stopped', {'reason': 'write_errors'});
        }
        return;
      }
      if (!current()) return;
      _writeFailures = 0;
      _record('diagnostic_write_ack', context);
      final received = await reply.future.timeout(
        const Duration(seconds: 2),
        onTimeout: () => false,
      );
      if (!current()) return;
      if (received) {
        matchingReplies++;
      } else {
        unansweredQueries++;
      }
      // Status notifications can arrive unsolicited: matching is not proof of causality.
      _record(
        received ? 'diagnostic_matching_frame' : 'diagnostic_response_timeout',
        context,
      );
    } finally {
      if (generation == _generation) {
        _pendingReply = null;
        _pendingQuery = null;
        querying = false;
        notifyListeners();
      }
    }
  }

  bool recordConsole(String speedText, String distanceText) {
    if (!active) return false;
    final speed = double.tryParse(speedText.trim().replaceAll(',', '.'));
    final distance = double.tryParse(distanceText.trim().replaceAll(',', '.'));
    if (speed == null ||
        distance == null ||
        !speed.isFinite ||
        !distance.isFinite ||
        speed < 0 ||
        distance < 0) {
      return false;
    }
    _record('console_reference', {'speed_kmh': speed, 'distance_km': distance});
    return true;
  }

  void mark(String label) {
    if (active) _record('marker', {'label': label});
  }

  void lifecycle(String state) {
    if (active) _record('app_lifecycle', {'state': state});
  }

  Future<void> stop() async {
    if (_stopping) return;
    if (!active && _connection == null) {
      log?.close();
      return;
    }
    _trainingTimer?.cancel();
    try {
      training?.finish(complete: false);
    } catch (_) {
      error =
          'No se pudo cerrar la sesión; se conservan las muestras guardadas.';
    }
    refreshHistory();
    _stopping = true;
    busy = true;
    active = false;
    _generation++;
    _pollTimer?.cancel();
    _pollTimer = null;
    if (_pendingReply != null && !_pendingReply!.isCompleted) {
      _pendingReply!.complete(false);
    }
    _pendingReply = null;
    _pendingQuery = null;
    querying = false;
    _deviceId = null;
    final connection = _connection;
    _connection = null;
    final subscriptions = List.of(_notifications);
    _notifications.clear();
    try {
      for (final subscription in subscriptions) {
        await subscription.cancel();
      }
      await connection?.cancel();
      _record('session_end', {'packets': packets});
    } catch (e) {
      error = 'Error al cerrar la conexión: $e';
    } finally {
      log?.close();
      try {
        try {
          await _startingKeepAwake;
        } catch (_) {
          // A failed start still needs native cleanup.
        }
        _startingKeepAwake = null;
        await _keepAwake(false);
      } catch (_) {
        error ??= 'No se pudo cerrar el servicio de grabación.';
      }
      _stopping = false;
      busy = false;
      status = 'Conexión finalizada · datos guardados';
      notifyListeners();
    }
  }

  Future<void> share(File file) async {
    try {
      await SharePlus.instance.share(
        ShareParams(files: [XFile(file.path)], text: 'Datos de SimpleRunning'),
      );
    } catch (e) {
      error = 'No se pudo compartir: $e';
      notifyListeners();
    }
  }
}
