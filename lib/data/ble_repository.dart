import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';

import 'fitshow_diagnostics.dart';

class BleRepository {
  BleRepository(this.client);
  final FlutterReactiveBle client;

  Stream<DiscoveredDevice> scan() =>
      client.scanForDevices(withServices: [], scanMode: ScanMode.lowLatency);

  Stream<ConnectionStateUpdate> connect(String id) => client.connectToDevice(
    id: id,
    connectionTimeout: const Duration(seconds: 15),
  );

  Future<List<Service>> discover(String id) async {
    await client.discoverAllServices(id);
    return client.getDiscoveredServices(id);
  }

  // Restrict writes to known diagnostic queries on the FitShow channel.
  Future<void> queryFitShow(String id, FitShowQuery query) =>
      sendFitShow(id, query.bytes);

  // Some FitShow consoles advertise only Write Request on FFF2 but accept
  // ATT Write Command for initialization and polling.
  Future<void> initializeFitShow(String id) async {
    // Anonymous session slot, with personal profile fields left unset.
    await sendFitShow(id, fitShowFrame([0x53, 0, 1, 0, 0, 0, 0]));
    await Future<void>.delayed(const Duration(milliseconds: 350));
    await sendFitShow(id, fitShowClock(DateTime.now()));
    for (final query in [0x02, 0x03, 0x04]) {
      await Future<void>.delayed(const Duration(milliseconds: 350));
      await sendFitShow(id, fitShowFrame([0x50, query]));
    }
  }

  Future<void> sendFitShow(String id, List<int> bytes) => client
      .writeCharacteristicWithoutResponse(
        QualifiedCharacteristic(
          deviceId: id,
          serviceId: Uuid.parse('fff0').expanded,
          characteristicId: Uuid.parse('fff2').expanded,
        ),
        value: bytes,
      )
      .timeout(const Duration(seconds: 5));

  Future<List<int>> read(String id, Characteristic c) =>
      c.read().timeout(const Duration(seconds: 8));

  Stream<List<int>> subscribe(String id, Characteristic c) => c.subscribe();
}
