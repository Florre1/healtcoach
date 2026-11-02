import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:permission_handler/permission_handler.dart';

final scaleService = Uuid.parse('0000ffe0-0000-1000-8000-00805f9b34fb');
final scaleCharacteristic = Uuid.parse('0000ffe1-0000-1000-8000-00805f9b34fb');

String bluetoothStatusMessage(BleStatus status) => switch (status) {
  BleStatus.poweredOff => 'Schalte Bluetooth am Handy ein und suche erneut.',
  BleStatus.locationServicesDisabled => 'Aktiviere die Standortfunktion für die Bluetooth-Suche auf dieser Android-Version.',
  BleStatus.unsupported =>
    'Dieses Gerät unterstützt kein Bluetooth Low Energy.',
  BleStatus.unauthorized => 'Bluetooth-Zugriff fehlt. Prüfe die Freigaben in den Android-App-Einstellungen.',
  _ => 'Bluetooth ist noch nicht bereit. Bitte erneut suchen.',
};

class BluetoothUnavailable implements Exception {
  final String message;
  const BluetoothUnavailable(this.message);
  @override
  String toString() => message;
}

/// Platform permissions and GATT are separate from the session state machine.
abstract interface class BleTransport {
  Future<void> prepare({required bool requestPermission});
  Stream<BleStatus> get status;
  Stream<DiscoveredDevice> scan();
  Stream<ConnectionStateUpdate> connect(String deviceId);
  Future<void> validate(String deviceId);
  Stream<List<int>> notifications(String deviceId);
  Future<void> write(String deviceId, List<int> bytes);
}

class AndroidBleTransport implements BleTransport {
  final FlutterReactiveBle _ble = FlutterReactiveBle();
  final _writeWithResponse = <String, bool>{};
  QualifiedCharacteristic _target(String id) => QualifiedCharacteristic(
    deviceId: id,
    serviceId: scaleService,
    characteristicId: scaleCharacteristic,
  );

  @override
  Future<void> prepare({required bool requestPermission}) async {
    final sdk = (await DeviceInfoPlugin().androidInfo).version.sdkInt;
    final permissions = sdk >= 31
        ? [Permission.bluetoothScan, Permission.bluetoothConnect]
        : [Permission.locationWhenInUse];
    for (final permission in permissions) {
      var result = await permission.status;
      if (!result.isGranted && requestPermission) {
        result = await permission.request();
      }
      if (!result.isGranted) {
        throw BluetoothUnavailable(
          result.isPermanentlyDenied
              ? 'Bluetooth-Zugriff fehlt. Erlaube die benötigten Freigaben in den Android-App-Einstellungen.'
              : sdk >= 31
              ? 'Erlaube Geräte in der Nähe, damit die App deine Waage findet.'
              : 'Android benötigt die Standortfreigabe für die Bluetooth-Suche.',
        );
      }
    }
    // This stream initializes the plugin, including on a cold app launch.
    final current = await status
        .firstWhere((s) => s != BleStatus.unknown)
        .timeout(const Duration(seconds: 5));
    if (current != BleStatus.ready) {
      throw BluetoothUnavailable(bluetoothStatusMessage(current));
    }
  }

  @override
  Stream<BleStatus> get status => _ble.statusStream;
  @override
  Stream<DiscoveredDevice> scan() =>
      _ble.scanForDevices(withServices: [], scanMode: ScanMode.lowLatency);
  @override
  Stream<ConnectionStateUpdate> connect(String deviceId) =>
      _ble.connectToDevice(
        id: deviceId,
        connectionTimeout: const Duration(seconds: 12),
        servicesWithCharacteristicsToDiscover: {
          scaleService: [scaleCharacteristic],
        },
      );
  @override
  Future<void> validate(String deviceId) async {
    _writeWithResponse.remove(deviceId);
    final services = await _ble.getDiscoveredServices(deviceId);
    final characteristics = services
        .where((s) => s.id == scaleService)
        .expand((s) => s.characteristics)
        .where((c) => c.id == scaleCharacteristic);
    final target = characteristics
        .where(
          (c) =>
              (c.isWritableWithResponse || c.isWritableWithoutResponse) &&
              (c.isNotifiable || c.isIndicatable),
        )
        .firstOrNull;
    if (target == null) {
      throw const BluetoothUnavailable(
        'Die Waage bietet den erwarteten SBF-70-Dienst nicht an. Bitte Bluetooth-Diagnose speichern.',
      );
    }
    _writeWithResponse[deviceId] = target.isWritableWithResponse;
  }

  @override
  Stream<List<int>> notifications(String deviceId) =>
      _ble.subscribeToCharacteristic(_target(deviceId));
  @override
  Future<void> write(String deviceId, List<int> bytes) {
    final withResponse = _writeWithResponse[deviceId];
    if (withResponse == null) {
      throw const BluetoothUnavailable('Bluetooth-Dienst noch nicht geprüft.');
    }
    return withResponse
        ? _ble.writeCharacteristicWithResponse(_target(deviceId), value: bytes)
        : _ble.writeCharacteristicWithoutResponse(
            _target(deviceId),
            value: bytes,
          );
  }
}
