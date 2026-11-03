import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:fake_async/fake_async.dart';
import 'package:flutter/material.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simplerunning/data/app_preferences.dart';
import 'package:simplerunning/ui/capture_model.dart';
import 'package:simplerunning/ui/capture_screen.dart';

import 'capture_model_test.dart' show FakeBle, FakeService;

class AutoConnectBle extends FakeBle {
  final advertisements = StreamController<DiscoveredDevice>.broadcast();
  final _connection = StreamController<ConnectionStateUpdate>.broadcast();
  final _notifications = StreamController<List<int>>.broadcast();
  @override
  StreamController<ConnectionStateUpdate> get connection => _connection;
  @override
  StreamController<List<int>> get notifications => _notifications;
  final connectedIds = <String>[];
  int preparations = 0;
  Future<void>? preparation;

  @override
  Future<void> prepareScan() async {
    preparations++;
    await preparation;
  }

  @override
  Stream<DiscoveredDevice> scan() => advertisements.stream;

  @override
  Stream<ConnectionStateUpdate> connect(String id) {
    connectedIds.add(id);
    return super.connect(id);
  }
}

DiscoveredDevice device(String id, [String name = 'Mi cinta']) =>
    DiscoveredDevice(
      id: id,
      name: name,
      serviceData: {},
      serviceUuids: [],
      manufacturerData: Uint8List(0),
      rssi: -50,
    );

Future<void> settle() => Future<void>.delayed(Duration.zero);

void main() {
  late AutoConnectBle ble;
  late AppPreferences preferences;
  late CaptureModel model;

  setUp(() {
    ble = AutoConnectBle();
    preferences = AppPreferences(null)
      ..set('treadmill', {'id': 'saved', 'name': 'Mi cinta'});
    model = CaptureModel(
      ble,
      null,
      preferences: preferences,
      keepAwake: (_) async {},
    );
  });

  tearDown(() async {
    await model.stopScan();
    await model.stop();
    model.dispose();
    await ble.advertisements.close();
    await ble.connection.close();
    await ble.notifications.close();
  });

  test(
    'crowded scans hide unrelated devices and keep the saved treadmill first',
    () async {
      await model.scan();
      for (var index = 0; index < 100; index++) {
        ble.advertisements.add(device('nearby-$index', 'Nearby device $index'));
      }
      ble.advertisements.add(
        device(
          'fitshow',
          'Console',
        ).copyWith(serviceUuids: [Uuid.parse('fff0').expanded]),
      );
      ble.advertisements.add(
        device('ftms', '').copyWith(serviceUuids: [Uuid.parse('1826')]),
      );
      ble.advertisements.add(device('saved', ''));
      await settle();
      expect(model.devices.map((d) => d.id), ['saved', 'fitshow', 'ftms']);
      expect(model.hiddenDeviceCount, 100);
      expect(ble.connectedIds, isEmpty);
      model.setShowAllDevices(true);
      expect(model.devices, hasLength(103));
      expect(model.devices.first.id, 'saved');
      expect(model.devices[1].id, 'fitshow');
      model.setShowAllDevices(false);
      expect(model.devices, hasLength(3));
    },
  );

  test(
    'service data and console names identify candidates without service UUIDs',
    () async {
      await model.scan();
      ble.advertisements.add(device('tf', 'TF-TEST'));
      ble.advertisements.add(device('named', 'FitShow console'));
      ble.advertisements.add(
        device(
          'data',
          '',
        ).copyWith(serviceData: {Uuid.parse('fff0').expanded: Uint8List(0)}),
      );
      ble.advertisements.add(device('headphones', 'Headphones'));
      await settle();
      expect(model.devices.map((d) => d.id), ['tf', 'named', 'data']);
    },
  );

  test(
    'partial advertisements preserve the treadmill name and services',
    () async {
      await model.scan();
      ble.advertisements.add(
        device(
          'console',
          'My console',
        ).copyWith(serviceUuids: [Uuid.parse('fff0').expanded]),
      );
      ble.advertisements.add(device('console', '').copyWith(rssi: -70));
      await settle();
      expect(model.devices.single.name, 'My console');
      expect(model.devices.single.serviceUuids, [Uuid.parse('fff0').expanded]);
      expect(model.devices.single.rssi, -70);
      expect(model.hiddenDeviceCount, 0);
      model.setShowAllDevices(true);
      await model.stopScan();
      await model.scan();
      expect(model.devices, isEmpty);
      expect(model.showAllDevices, isFalse);
    },
  );

  testWidgets(
    'scan list filters noise and allows selecting an unrecognized treadmill',
    (tester) async {
      await tester.runAsync(() async {
        await model.restoreConnection();
        ble.advertisements.add(device('console', 'TF-TEST'));
        ble.advertisements.add(device('unknown', 'Other console'));
        await settle();
        await model.stopScan();
      });
      await tester.pumpWidget(MaterialApp(home: CaptureScreen(model: model)));
      await tester.scrollUntilVisible(find.text('TF-TEST'), 250);
      await tester.pumpAndSettle();
      expect(find.text('Other console'), findsNothing);
      await tester.ensureVisible(find.text('Mostrar todos (1 más)'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Mostrar todos (1 más)'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('Other console'), 150);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Other console'));
      await tester.runAsync(settle);
      await tester.pumpAndSettle();
      expect(ble.connectedIds, ['unknown']);
      expect(tester.takeException(), isNull);
      unawaited(model.stop());
      await tester.runAsync(settle);
      await tester.pumpAndSettle();
    },
  );

  test(
    'first launch and invalid saved devices do not request Bluetooth',
    () async {
      for (final saved in [
        null,
        42,
        {'id': ''},
        {'id': 123},
      ]) {
        final prefs = AppPreferences(null)..set('treadmill', saved);
        final fresh = CaptureModel(ble, null, preferences: prefs);
        await fresh.restoreConnection();
        expect(ble.preparations, 0);
        expect(fresh.scanning, isFalse);
        fresh.dispose();
      }
    },
  );

  test(
    'startup connects only to the saved ID, once, without starting training',
    () async {
      await model.restoreConnection();
      await model.restoreConnection();
      expect(ble.preparations, 1);
      ble.advertisements.add(device('other')); // Same name is not sufficient.
      await settle();
      expect(ble.connectedIds, isEmpty);
      ble.advertisements.add(device('saved'));
      ble.advertisements.add(device('saved'));
      await settle();
      expect(ble.connectedIds, ['saved']);
      expect(model.scanning, isFalse);
      ble.connection.add(
        const ConnectionStateUpdate(
          deviceId: 'saved',
          connectionState: DeviceConnectionState.connected,
          failure: null,
        ),
      );
      ble.discovered.complete([FakeService()]);
      await settle();
      expect(model.canStartTraining, isTrue);
      expect(model.trainingActive, isFalse);
      expect(ble.initializations, 0);
      expect(ble.commands, isEmpty);
      await model.stop();
      await model.restoreConnection();
      expect(ble.preparations, 1); // Explicit disconnect stays disconnected.
    },
  );

  test('compatible selection survives restart and can be forgotten', () async {
    final directory = Directory.systemTemp.createTempSync(
      'remember_treadmill_',
    );
    addTearDown(() => directory.deleteSync(recursive: true));
    final file = File('${directory.path}/preferences.json');
    final persistent = AppPreferences(file)..set('voice', false);
    final first = CaptureModel(
      ble,
      null,
      preferences: persistent,
      keepAwake: (_) async {},
    );
    await first.connect(device('new', 'Cinta nueva'));
    expect(persistent.treadmillId, isNull);
    ble.connection.add(
      const ConnectionStateUpdate(
        deviceId: 'new',
        connectionState: DeviceConnectionState.connected,
        failure: null,
      ),
    );
    ble.discovered.complete([FakeService()]);
    await settle();
    await first.stop();
    first.dispose();
    final restored = AppPreferences(file);
    expect(restored.treadmillId, 'new');
    expect(restored.treadmillName, 'Cinta nueva');
    final nextBle = AutoConnectBle();
    final next = CaptureModel(nextBle, null, preferences: restored);
    await next.restoreConnection();
    expect(next.scanning, isTrue);
    await next.forgetTreadmill();
    nextBle.advertisements.add(device('new'));
    await settle();
    expect(nextBle.connectedIds, isEmpty);
    expect(AppPreferences(file).treadmillId, isNull);
    expect(AppPreferences(file).voice, isFalse);
    next.dispose();
    await nextBle.advertisements.close();
    await nextBle.connection.close();
    await nextBle.notifications.close();
  });

  test('incompatible devices never replace the saved treadmill', () async {
    await model.connect(device('incompatible'));
    ble.connection.add(
      const ConnectionStateUpdate(
        deviceId: 'incompatible',
        connectionState: DeviceConnectionState.connected,
        failure: null,
      ),
    );
    ble.discovered.complete([FakeService(notify: false)]);
    await settle();
    expect(preferences.treadmillId, 'saved');
    expect(model.canStartTraining, isFalse);
  });

  test(
    'failed connection retains the saved treadmill and permits manual search',
    () async {
      await model.restoreConnection();
      ble.advertisements.add(device('saved'));
      await settle();
      ble.connection.addError(StateError('connection timed out'));
      await settle();
      expect(model.active, isFalse);
      expect(model.busy, isFalse);
      expect(preferences.treadmillId, 'saved');
      await model.scan();
      expect(model.scanning, isTrue);
    },
  );

  test('unavailable treadmill ends the scan after 15 seconds', () async {
    fakeAsync((time) {
      unawaited(model.restoreConnection());
      time.flushMicrotasks();
      expect(model.scanning, isTrue);
      time.elapse(const Duration(seconds: 15));
      expect(model.scanning, isFalse);
      expect(preferences.treadmillId, 'saved');
      expect(ble.connectedIds, isEmpty);
      time.elapse(const Duration(minutes: 1));
      expect(ble.preparations, 1);
    });
    // Broadcast subscription cancellation completes outside the fake clock.
    await settle();
    expect(model.status, contains('No se encontró'));
  });

  test(
    'cancelled automatic scan cannot connect and manual scan allows selection',
    () async {
      await model.restoreConnection();
      await model.stopScan();
      ble.advertisements.add(device('saved'));
      await settle();
      expect(ble.connectedIds, isEmpty);
      await model.scan();
      ble.advertisements.add(device('saved'));
      ble.advertisements.add(device('other'));
      await settle();
      expect(ble.connectedIds, isEmpty);
      await model.connect(device('other'));
      expect(ble.connectedIds, ['other']);
    },
  );

  test(
    'permission or Bluetooth failure leaves manual retry available',
    () async {
      ble.preparation = Future<void>.error(StateError('Bluetooth unavailable'));
      await model.restoreConnection();
      expect(model.scanning, isFalse);
      expect(model.busy, isFalse);
      expect(model.error, contains('Bluetooth'));
      ble.preparation = null;
      await model.scan();
      expect(model.scanning, isTrue);
    },
  );

  test('cancel while preparing Bluetooth prevents a late scan', () async {
    final ready = Completer<void>();
    ble.preparation = ready.future;
    final restoring = model.restoreConnection();
    await model.stopScan();
    ready.complete();
    await restoring;
    expect(model.scanning, isFalse);
    expect(model.busy, isFalse);
    expect(ble.advertisements.hasListener, isFalse);
  });

  test(
    'disposing during connection setup cannot start a late connection',
    () async {
      final closing = CaptureModel(ble, null, keepAwake: (_) async {});
      final connecting = closing.connect(device('saved'));
      closing.dispose();
      await connecting;
      expect(ble.connectedIds, isEmpty);
      expect(closing.active, isFalse);
    },
  );

  testWidgets(
    'opening the screen searches and Settings can forget the treadmill',
    (tester) async {
      await tester.pumpWidget(MaterialApp(home: CaptureScreen(model: model)));
      await tester.pump();
      expect(ble.preparations, 1);
      expect(model.scanning, isTrue);
      await tester.tap(find.byTooltip('Ajustes'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Mi cinta'), findsOneWidget);
      await tester.tap(find.text('Olvidar'));
      await tester.runAsync(settle);
      await tester.pumpAndSettle();
      expect(preferences.treadmillId, isNull);
      expect(model.scanning, isFalse);
      expect(find.text('Olvidar'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
