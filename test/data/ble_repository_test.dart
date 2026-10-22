import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:flutter_test/flutter_test.dart';
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
