import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fake_async/fake_async.dart';
import 'package:simplerunning/data/ble_repository.dart';
import 'package:simplerunning/data/capture_log.dart';
import 'package:simplerunning/data/training_store.dart';
import 'package:simplerunning/domain/workout.dart';
import 'package:simplerunning/data/fitshow_diagnostics.dart';
import 'package:simplerunning/ui/capture_model.dart';

class FakeBle implements BleRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnsupportedError(
    'Unexpected BLE operation: ${invocation.memberName}',
  );
  int initializations = 0;
  Future<void>? initialization;
  final commands = <List<int>>[];
  @override
  Future<void> initializeFitShow(String id) async {
    initializations++;
    await initialization;
  }

  @override
  Future<void> sendFitShow(String id, List<int> bytes) async {
    commands.add(bytes);
  }

  final notifications = StreamController<List<int>>();
  final writes = <FitShowQuery>[];
  bool failWrites = false;
  final writeCompletion = Completer<void>();
  @override
  Stream<List<int>> subscribe(String id, Characteristic c) =>
      notifications.stream;
  @override
  Future<void> queryFitShow(String id, FitShowQuery query) {
    writes.add(query);
    if (failWrites) return Future.error(StateError('synthetic failure'));
    return writeCompletion.future;
  }

  final connection = StreamController<ConnectionStateUpdate>();
  final discovered = Completer<List<Service>>();
  @override
  Stream<ConnectionStateUpdate> connect(String id) => connection.stream;
  @override
  Future<List<Service>> discover(String id) => discovered.future;
}

class FakeService implements Service {
  FakeService({
    this.notify = true,
    this.writeWithResponse = true,
    this.writeWithoutResponse = false,
  });
  final bool notify;
  final bool writeWithResponse;
  final bool writeWithoutResponse;
  @override
  Uuid get id => Uuid.parse('fff0').expanded;
  @override
  List<Characteristic> get characteristics => [
    FakeCharacteristic(this, 'fff1', notify: notify),
    FakeCharacteristic(
      this,
      'fff2',
      writable: writeWithResponse,
      writeWithoutResponse: writeWithoutResponse,
    ),
  ];
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class FakeCharacteristic implements Characteristic {
  FakeCharacteristic(
    this.service,
    this.shortId, {
    this.notify = false,
    this.writable = false,
    this.writeWithoutResponse = false,
  });
  @override
  final Service service;
  final String shortId;
  final bool notify;
  final bool writable;
  final bool writeWithoutResponse;
  @override
  Uuid get id => Uuid.parse(shortId).expanded;
  @override
  bool get isReadable => false;
  @override
  bool get isNotifiable => notify;
  @override
  bool get isIndicatable => false;
  @override
  bool get isWritableWithResponse => writable;
  @override
  bool get isWritableWithoutResponse => writeWithoutResponse;
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class ManualStopwatch implements Stopwatch {
  int seconds = 0;
  @override
  bool isRunning = false;
  @override
  Duration get elapsed => Duration(seconds: seconds);
  @override
  void start() {
    isRunning = true;
  }

  @override
  void stop() {
    isRunning = false;
  }

  @override
  void reset() {
    seconds = 0;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

void main() {
  DiscoveredDevice device() => DiscoveredDevice(
    id: 'synthetic',
    name: '',
    serviceData: {},
    serviceUuids: [],
    manufacturerData: Uint8List(0),
    rssi: -50,
  );

  for (final (withResponse, withoutResponse) in [
    (true, false), // Target console: FFF2 advertises only Write Request.
    (false, true),
    (true, true),
  ]) {
    test(
      'quiet console starts with write=$withResponse, command=$withoutResponse',
      () async {
        final directory = Directory.systemTemp.createTempSync('quiet_console_');
        final ble = FakeBle()..writeCompletion.complete();
        final model = CaptureModel(
          ble,
          null,
          training: TrainingStore(directory),
          keepAwake: (_) async {},
        );
        addTearDown(() async {
          await model.stop();
          await ble.connection.close();
          await ble.notifications.close();
          model.dispose();
          directory.deleteSync(recursive: true);
        });
        await model.connect(device());
        expect(model.canStartTraining, isFalse);
        ble.connection.add(
          const ConnectionStateUpdate(
            deviceId: 'synthetic',
            connectionState: DeviceConnectionState.connected,
            failure: null,
          ),
        );
        ble.discovered.complete([
          FakeService(
            writeWithResponse: withResponse,
            writeWithoutResponse: withoutResponse,
          ),
        ]);
        await Future<void>.delayed(Duration.zero);
        expect(model.packets, 0);
        expect(model.canStartTraining, isTrue);
        await model.startTraining();
        expect(ble.initializations, 1);
        expect(model.trainingActive, isTrue);
        expect(model.canStartTraining, isFalse);
        await model.startTraining();
        expect(ble.initializations, 1);
        ble.notifications.add(
          fitShowFrame([0x51, 3, 60, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]),
        );
        await Future<void>.delayed(Duration.zero);
        expect(model.liveSpeed, 6);
        expect(model.polling, isTrue);
        await model.stop();
        expect(model.canStartTraining, isFalse);
      },
    );
  }

  test('quiet target console is polled after initialization without unsolicited status', () {
    fakeAsync((time) {
      final directory = Directory.systemTemp.createTempSync('quiet_polling_');
      final initialized = Completer<void>();
      final ble = FakeBle()
        ..writeCompletion.complete()
        ..initialization = initialized.future;
      final model = CaptureModel(
        ble,
        null,
        training: TrainingStore(directory),
        keepAwake: (_) async {},
      );
      unawaited(model.connect(device()));
      time.flushMicrotasks();
      ble.connection.add(
        const ConnectionStateUpdate(
          deviceId: 'synthetic',
          connectionState: DeviceConnectionState.connected,
          failure: null,
        ),
      );
      ble.discovered.complete([FakeService()]);
      time.flushMicrotasks();
      time.elapse(const Duration(seconds: 3));
      expect(ble.writes, isEmpty);
      expect(model.canStartTraining, isTrue);
      unawaited(model.startTraining());
      time.flushMicrotasks();
      expect(ble.initializations, 1);
      time.elapse(const Duration(seconds: 3));
      expect(ble.writes, isEmpty);
      expect(model.polling, isFalse);
      expect(model.trainingActive, isFalse);
      initialized.complete();
      time.flushMicrotasks();
      expect(model.trainingActive, isTrue);
      expect(model.polling, isTrue);
      expect(model.liveSpeed, isNull);
      time.elapse(const Duration(seconds: 1));
      expect(ble.writes, [FitShowQuery.status]);
      // The console responds only after the app requests its first status.
      ble.notifications.add(
        fitShowFrame([0x51, 3, 60, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]),
      );
      time.flushMicrotasks();
      expect(model.liveSpeed, 6);
      expect(model.matchingReplies, 1);
      time.elapse(const Duration(seconds: 1));
      expect(ble.writes.last, FitShowQuery.workout);
      ble.notifications.add(fitShowFrame([0x52, 0, 0, 0, 100, 0, 0, 0, 0, 0]));
      time.flushMicrotasks();
      expect(model.workout!.distanceRaw, 100);
      unawaited(model.stop());
      time.flushMicrotasks();
      final writes = ble.writes.length;
      time.elapse(const Duration(seconds: 5));
      expect(ble.writes, hasLength(writes));
      expect(model.canStartTraining, isFalse);
      expect(model.polling, isFalse);
      unawaited(ble.notifications.close());
      unawaited(ble.connection.close());
      time.flushMicrotasks();
      model.dispose();
      directory.deleteSync(recursive: true);
    });
  });

  for (final service in [
    FakeService(notify: false),
    FakeService(writeWithResponse: false, writeWithoutResponse: false),
  ]) {
    test(
      'missing required FitShow channel explains unavailable start',
      () async {
        final ble = FakeBle();
        final model = CaptureModel(ble, null, keepAwake: (_) async {});
        await model.connect(device());
        ble.connection.add(
          const ConnectionStateUpdate(
            deviceId: 'synthetic',
            connectionState: DeviceConnectionState.connected,
            failure: null,
          ),
        );
        ble.discovered.complete([service]);
        await Future<void>.delayed(Duration.zero);
        expect(model.canStartTraining, isFalse);
        expect(model.status, isNot(contains('lista para entrenar')));
        expect(model.error, contains('canales FitShow'));
        await model.startTraining();
        expect(ble.initializations, 0);
        await model.stop();
        unawaited(ble.notifications.close());
        await ble.connection.close();
        model.dispose();
      },
    );
  }

  test(
    'failed background service cancels connection and releases resources',
    () async {
      final ble = FakeBle();
      final states = <bool>[];
      final model = CaptureModel(
        ble,
        null,
        keepAwake: (enabled) async {
          states.add(enabled);
          if (enabled) throw StateError('Service unavailable');
        },
      );
      await model.connect(device());
      expect(model.active, isFalse);
      expect(model.busy, isFalse);
      expect(ble.connection.hasListener, isFalse);
      expect(states, [true, false]);
      expect(model.error, contains('Service unavailable'));
      unawaited(ble.connection.close());
      unawaited(ble.notifications.close());
      model.dispose();
    },
  );

  test('stop waits for pending service startup before releasing it', () async {
    final ble = FakeBle();
    final started = Completer<void>();
    final states = <bool>[];
    final model = CaptureModel(
      ble,
      null,
      keepAwake: (enabled) async {
        states.add(enabled);
        if (enabled) await started.future;
      },
    );
    final connecting = model.connect(device());
    await Future<void>.delayed(Duration.zero);
    final stopping = model.stop();
    await Future<void>.delayed(Duration.zero);
    expect(states, [true]);
    started.complete();
    await connecting;
    await stopping;
    expect(states, [true, false]);
    expect(model.active, isFalse);
    expect(ble.connection.hasListener, isFalse);
    unawaited(ble.connection.close());
    unawaited(ble.notifications.close());
    model.dispose();
  });

  test('timed workout finishes automatically, persists goal and stops console once', () {
    fakeAsync((time) {
      final directory = Directory.systemTemp.createTempSync('auto_finish_');
      final clock = ManualStopwatch();
      final store = TrainingStore(
        Directory('${directory.path}/sessions'),
        clock: clock,
      );
      final ble = FakeBle()..writeCompletion.complete();
      final model = CaptureModel(
        ble,
        CaptureLog(Directory('${directory.path}/captures')),
        training: store,
        keepAwake: (_) async {},
      );
      model.selectWorkout(
        const WorkoutRecipe('synthetic-plan', 'Test session', [
          WorkoutBlock(BlockKind.run, 'Run', seconds: 5),
        ]),
      );
      unawaited(
        model.connect(
          DiscoveredDevice(
            id: 'synthetic',
            name: '',
            serviceData: {},
            serviceUuids: [],
            manufacturerData: Uint8List(0),
            rssi: -50,
          ),
        ),
      );
      time.flushMicrotasks();
      ble.connection.add(
        const ConnectionStateUpdate(
          deviceId: 'synthetic',
          connectionState: DeviceConnectionState.connected,
          failure: null,
        ),
      );
      ble.discovered.complete([FakeService()]);
      time.flushMicrotasks();
      ble.notifications.add(fitShowFrame([0x51, 0]));
      time.flushMicrotasks();
      unawaited(model.startTraining());
      time.flushMicrotasks();
      // Locking the screen must not stop sampling or automatic completion.
      model.lifecycle('inactive');
      model.lifecycle('hidden');
      model.lifecycle('paused');
      clock.seconds = 5;
      time.elapse(const Duration(seconds: 1));
      time.flushMicrotasks();
      time.elapse(const Duration(seconds: 5));
      time.flushMicrotasks();
      expect(model.trainingActive, isFalse);
      expect(model.history.single.goalReached, isTrue);
      expect(model.history.single.seconds, 5);
      expect(ble.commands, hasLength(1));
      expect(fitShowPayload(ble.commands.single), [0x53, 3]);
      unawaited(ble.notifications.close());
      unawaited(ble.connection.close());
      time.flushMicrotasks();
      model.dispose();
      directory.deleteSync(recursive: true);
    });
  });

  for (final interrupted in [false, true]) {
    test('training persistence with interrupted=$interrupted', () {
      fakeAsync((clock) {
        final directory = Directory.systemTemp.createTempSync(
          'training_model_',
        );
        final store = TrainingStore(Directory('${directory.path}/sessions'));
        final ble = FakeBle()..writeCompletion.complete();
        final model = CaptureModel(
          ble,
          null,
          training: store,
          keepAwake: (_) async {},
        );
        unawaited(
          model.connect(
            DiscoveredDevice(
              id: 'synthetic',
              name: '',
              serviceData: {},
              serviceUuids: [],
              manufacturerData: Uint8List(0),
              rssi: -50,
            ),
          ),
        );
        clock.flushMicrotasks();
        ble.connection.add(
          const ConnectionStateUpdate(
            deviceId: 'synthetic',
            connectionState: DeviceConnectionState.connected,
            failure: null,
          ),
        );
        ble.discovered.complete([FakeService()]);
        clock.flushMicrotasks();
        ble.notifications.add(fitShowFrame([0x51, 0]));
        clock.flushMicrotasks();
        unawaited(model.startTraining());
        clock.flushMicrotasks();
        expect(ble.initializations, 1);
        expect(model.trainingActive, isTrue);
        ble.notifications.add(
          fitShowFrame([0x51, 3, 60, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]),
        );
        ble.notifications.add(
          fitShowFrame([0x52, 0, 0, 0, 100, 0, 0, 0, 0, 0]),
        );
        clock.flushMicrotasks();
        ble.notifications.add(
          fitShowFrame([0x52, 0, 0, 0, 120, 0, 0, 0, 0, 0]),
        );
        clock.flushMicrotasks();
        clock.elapse(const Duration(seconds: 1));
        expect(model.liveSpeed, 6);
        if (interrupted) {
          ble.connection.add(
            const ConnectionStateUpdate(
              deviceId: 'synthetic',
              connectionState: DeviceConnectionState.disconnected,
              failure: null,
            ),
          );
        } else {
          unawaited(model.finishTraining());
        }
        clock.flushMicrotasks();
        clock.elapse(const Duration(seconds: 5));
        clock.flushMicrotasks();
        expect(model.trainingActive, isFalse);
        expect(model.history.single.meters, 20);
        expect(Directory('${directory.path}/captures').existsSync(), isFalse);
        expect(
          model.history.single.file.readAsStringSync(),
          isNot(contains('notification')),
        );
        expect(model.history.single.complete, !interrupted);
        expect(
          model.history.single.samples.any((s) => s['speed_kmh'] == 6),
          isTrue,
        );
        expect(ble.commands.length, interrupted ? 0 : 1);
        if (!interrupted) {
          expect(fitShowPayload(ble.commands.single), [0x53, 3]);
        }
        unawaited(ble.notifications.close());
        unawaited(ble.connection.close());
        clock.flushMicrotasks();
        model.dispose();
        directory.deleteSync(recursive: true);
      });
    });
  }

  for (final failWrites in [false, true]) {
    test(failWrites ? 'polling pauses after three write errors' : 'automatic polling matches replies, survives timeout and stops cleanly', () {
      fakeAsync((clock) {
        final directory = Directory.systemTemp.createTempSync(
          'auto_poll_test_',
        );
        final log = CaptureLog(directory);
        final ble = FakeBle()..failWrites = failWrites;
        ble.writeCompletion.complete();
        final model = CaptureModel(ble, log, keepAwake: (_) async {});
        unawaited(
          model.connect(
            DiscoveredDevice(
              id: 'synthetic',
              name: '',
              serviceData: {},
              serviceUuids: [],
              manufacturerData: Uint8List(0),
              rssi: -50,
            ),
          ),
        );
        clock.flushMicrotasks();
        ble.connection.add(
          const ConnectionStateUpdate(
            deviceId: 'synthetic',
            connectionState: DeviceConnectionState.connected,
            failure: null,
          ),
        );
        ble.discovered.complete([FakeService()]);
        clock.flushMicrotasks();
        clock.elapse(const Duration(seconds: 2));
        expect(ble.writes, isEmpty);
        ble.notifications.add([2, 0x51, 0, 0x51, 3]);
        clock.flushMicrotasks();
        expect(model.polling, isTrue);
        if (failWrites) {
          clock.elapse(const Duration(seconds: 5));
          expect(ble.writes, hasLength(3));
          expect(model.polling, isFalse);
          ble.notifications.add([2, 0x51, 0, 0x51, 3]);
          clock.flushMicrotasks();
          clock.elapse(const Duration(seconds: 2));
          expect(ble.writes, hasLength(3));
        } else {
          clock.elapse(const Duration(seconds: 1));
          expect(ble.writes, [FitShowQuery.workout]);
          expect(model.querying, isTrue); // Acknowledgment is not a response.
          ble.notifications.add([2, 0x51, 0, 0x51, 3]);
          clock.flushMicrotasks();
          expect(model.querying, isTrue); // Unrelated command must not match.
          final payload = [0x52, 0, 42, 0, 30, 0, 0, 0, 0, 0];
          ble.notifications.add([
            2,
            ...payload,
            payload.fold(0, (a, b) => a ^ b),
            3,
          ]);
          clock.flushMicrotasks();
          expect(model.workout!.elapsedSeconds, 42);
          expect(model.workout!.distanceRaw, 30);
          expect(model.matchingReplies, 1);
          expect(model.querying, isFalse);
          expect(model.recordConsole('4,5', '0.03'), isTrue);
          expect(model.recordConsole('NaN', '0'), isFalse);
          expect(model.recordConsole('-1', '0'), isFalse);
          expect(log.file!.readAsStringSync(), contains('console_reference'));
          clock.elapse(const Duration(seconds: 1));
          expect(ble.writes.last, FitShowQuery.status);
          clock.elapse(const Duration(seconds: 1));
          expect(ble.writes, hasLength(2)); // No overlapping query.
          clock.elapse(const Duration(seconds: 2));
          expect(model.unansweredQueries, greaterThanOrEqualTo(1));
          expect(ble.writes, contains(FitShowQuery.status));
        }
        unawaited(model.stop());
        clock.flushMicrotasks();
        final count = ble.writes.length;
        final contents = log.file!.readAsStringSync();
        clock.elapse(const Duration(seconds: 20));
        expect(ble.writes, hasLength(count));
        expect(log.file!.readAsStringSync(), contents);
        expect(model.polling, isFalse);
        unawaited(ble.notifications.close());
        unawaited(ble.connection.close());
        clock.flushMicrotasks();
        model.dispose();
        log.close();
        directory.deleteSync(recursive: true);
      });
    });
  }

  test('queries require a valid notification and stop after disconnect during a write', () async {
    final directory = Directory.systemTemp.createTempSync('probe_test_');
    final log = CaptureLog(directory);
    final ble = FakeBle();
    final model = CaptureModel(ble, log, keepAwake: (_) async {});
    await model.connect(
      DiscoveredDevice(
        id: 'synthetic',
        name: '',
        serviceData: {},
        serviceUuids: [],
        manufacturerData: Uint8List(0),
        rssi: -50,
      ),
    );
    ble.connection.add(
      const ConnectionStateUpdate(
        deviceId: 'synthetic',
        connectionState: DeviceConnectionState.connected,
        failure: null,
      ),
    );
    ble.discovered.complete([FakeService()]);
    await Future<void>.delayed(Duration.zero);
    expect(model.canQuery, isFalse);
    await model.queryData();
    expect(ble.writes, isEmpty);
    ble.notifications.add([2, 0x51, 3, 0, 3]);
    await Future<void>.delayed(Duration.zero);
    expect(model.canQuery, isFalse);
    ble.notifications.add([2, 0x51, 3, 0x52, 3]);
    await Future<void>.delayed(Duration.zero);
    expect(model.canQuery, isTrue);
    final query = model.queryData();
    expect(ble.writes, [FitShowQuery.workout]);
    await model.queryData(); // Repeated tap must not start another batch.
    expect(ble.writes, hasLength(1));
    await model.stop();
    final closed = log.file!.readAsStringSync();
    ble.writeCompletion.complete();
    await query;
    expect(ble.writes, hasLength(1));
    expect(log.file!.readAsStringSync(), closed);
    expect(model.canQuery, isFalse);
    expect(model.querying, isFalse);
    await ble.notifications.close();
    await ble.connection.close();
    model.dispose();
    log.close();
    directory.deleteSync(recursive: true);
  });
  test(
    'disconnect during discovery preserves capture and ignores late discovery',
    () async {
      final directory = Directory.systemTemp.createTempSync('model_test_');
      final log = CaptureLog(directory);
      final ble = FakeBle();
      final wakeStates = <bool>[];
      final model = CaptureModel(
        ble,
        log,
        keepAwake: (value) async {
          wakeStates.add(value);
        },
      );
      final device = DiscoveredDevice(
        id: 'private-id',
        name: 'private-name',
        serviceData: const {},
        serviceUuids: const [],
        manufacturerData: Uint8List(0),
        rssi: -50,
      );
      await model.connect(device);
      ble.connection.add(
        const ConnectionStateUpdate(
          deviceId: 'private-id',
          connectionState: DeviceConnectionState.connected,
          failure: null,
        ),
      );
      await Future<void>.delayed(Duration.zero);
      model.mark('Inicio');
      ble.connection.add(
        const ConnectionStateUpdate(
          deviceId: 'private-id',
          connectionState: DeviceConnectionState.disconnected,
          failure: null,
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(model.active, isFalse);
      expect(model.busy, isFalse);
      final before = log.file!.readAsStringSync();
      expect(before, contains('session_end'));
      expect(before, contains('Inicio'));
      expect(before, isNot(contains('private-id')));
      expect(before, isNot(contains('private-name')));
      ble.discovered.complete([]);
      await Future<void>.delayed(Duration.zero);
      expect(log.file!.readAsStringSync(), before);
      expect(wakeStates, [true, false]);
      await ble.connection.close();
      model.dispose();
      log.close();
      directory.deleteSync(recursive: true);
    },
  );
}
