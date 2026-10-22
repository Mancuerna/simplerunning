import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fake_async/fake_async.dart';

import 'dart:async';

import 'package:simplerunning/data/ble_repository.dart';
import 'package:simplerunning/data/fitshow_diagnostics.dart';

class WriteCommandClient implements FlutterReactiveBle {
  final writes = <List<int>>[];
  final channels = <QualifiedCharacteristic>[];

  @override
  Future<void> writeCharacteristicWithoutResponse(
    QualifiedCharacteristic characteristic, {
    required List<int> value,
  }) async {
    channels.add(characteristic);
    writes.add(value);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnsupportedError(
    'Unexpected BLE operation: ${invocation.memberName}',
  );
}

void main() {
  test(
    'initialization and stop use the FitShow ATT Write Command sequence',
    () {
      fakeAsync((time) {
        final client = WriteCommandClient();
        final repository = BleRepository(client);
        var initialized = false;
        unawaited(
          repository.initializeFitShow('synthetic').then((_) {
            initialized = true;
          }),
        );
        time.flushMicrotasks();
        expect(client.writes.map(fitShowPayload), [
          [0x53, 0, 1, 0, 0, 0, 0],
        ]);
        expect(initialized, isFalse);
        time.elapse(const Duration(milliseconds: 1400));
        expect(initialized, isTrue);
        expect(client.writes, hasLength(5));
        expect(fitShowPayload(client.writes[1])!.take(2), [0x50, 0]);
        expect(client.writes.skip(2).map(fitShowPayload), [
          [0x50, 2],
          [0x50, 3],
          [0x50, 4],
        ]);
        unawaited(repository.sendFitShow('synthetic', fitShowFrame([0x53, 3])));
        time.flushMicrotasks();
        expect(fitShowPayload(client.writes.last), [0x53, 3]);
        expect(
          client.channels.every(
            (c) =>
                c.serviceId == Uuid.parse('fff0').expanded &&
                c.characteristicId == Uuid.parse('fff2').expanded,
          ),
          isTrue,
        );
      });
    },
  );

  test(
    'polling uses the same ATT write command channel as initialization',
    () async {
      final client = WriteCommandClient();
      final repository = BleRepository(client);
      for (final query in FitShowQuery.values) {
        await repository.queryFitShow('synthetic', query);
      }
      expect(
        client.writes,
        FitShowQuery.values.map((query) => query.bytes).toList(),
      );
      for (final channel in client.channels) {
        expect(channel.deviceId, 'synthetic');
        expect(channel.serviceId, Uuid.parse('fff0').expanded);
        expect(channel.characteristicId, Uuid.parse('fff2').expanded);
      }
    },
  );
}
