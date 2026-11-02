import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';

import '../domain/models.dart';
import 'sanitas_protocol.dart';

enum ConnectionPhase { idle, scanning, connecting, synchronizing, ready, error }

class ScaleConnection extends ChangeNotifier {
  final FlutterReactiveBle _ble = FlutterReactiveBle();
  final Future<void> Function(Measurement) onReading;
  final Future<void> Function(Profile, String, String, String) onBound;
  ScaleConnection({required this.onReading, required this.onBound});
  static final service = Uuid.parse('0000ffe0-0000-1000-8000-00805f9b34fb');
  static final characteristic = Uuid.parse(
    '0000ffe1-0000-1000-8000-00805f9b34fb',
  );
  ConnectionPhase phase = ConnectionPhase.idle;
  String message = 'Verbinde deine Waage für die erste Messung.';
  String? connectedName;
  int? battery;
  double? liveWeight;
  final devices = <String, DiscoveredDevice>{};
  final List<String> diagnosticLog = [];
  StreamSubscription<DiscoveredDevice>? _scan;
  StreamSubscription<ConnectionStateUpdate>? _link;
  StreamSubscription<List<int>>? _notifications;
  Timer? _timeout;
  int _generation = 0;
  Future<void> _queue = Future.value();
  bool _disposed = false;
  bool get busy => [
    ConnectionPhase.scanning,
    ConnectionPhase.connecting,
    ConnectionPhase.synchronizing,
    ConnectionPhase.ready,
  ].contains(phase);
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  void _log(String line) {
    diagnosticLog.add('${DateTime.now().toIso8601String()} $line');
    if (diagnosticLog.length > 400) diagnosticLog.removeAt(0);
  }

  void _state(ConnectionPhase value, String text) {
    phase = value;
    message = text;
    _log(text);
    _notify();
  }

  Future<bool> _permissions(bool request) async {
    final sdk = (await DeviceInfoPlugin().androidInfo).version.sdkInt;
    final permissions = sdk >= 31
        ? [Permission.bluetoothScan, Permission.bluetoothConnect]
        : [Permission.locationWhenInUse];
    for (final permission in permissions) {
      var status = await permission.status;
      if (!status.isGranted && request) status = await permission.request();
      if (!status.isGranted) {
        _state(
          ConnectionPhase.error,
          status.isPermanentlyDenied
              ? 'Bluetooth-Zugriff fehlt. Erlaube „Geräte in der Nähe“ in den Android-App-Einstellungen.'
              : sdk >= 31
              ? 'Erlaube Geräte in der Nähe, damit die App deine Waage findet.'
              : 'Android benötigt die Standortfreigabe für die Bluetooth-Suche.',
        );
        return false;
      }
    }
    var status = _ble.status;
    if (status == BleStatus.unknown) {
      status = await _ble.statusStream
          .firstWhere((s) => s != BleStatus.unknown)
          .timeout(const Duration(seconds: 5));
    }
    if (status != BleStatus.ready) {
      _state(ConnectionPhase.error, switch (status) {
        BleStatus.poweredOff =>
          'Schalte Bluetooth am Handy ein und versuche es erneut.',
        BleStatus.locationServicesDisabled => 'Aktiviere die Standortfunktion für die Bluetooth-Suche auf dieser Android-Version.',
        BleStatus.unsupported =>
          'Dieses Gerät unterstützt kein Bluetooth Low Energy.',
        _ => 'Bluetooth ist noch nicht bereit. Prüfe die App-Berechtigungen.',
      });
      return false;
    }
    return true;
  }

  Future<void> scan(Profile profile, {bool automatic = false}) async {
    if (busy) return;
    await disconnect(quiet: true);
    final generation = _generation;
    devices.clear();
    liveWeight = null;
    battery = null;
    try {
      if (!await _permissions(!automatic) || generation != _generation) return;
      _state(
        ConnectionPhase.scanning,
        'Tippe die Waage kurz an. Suche nach Sanitas SBF 70 …',
      );
      _scan = _ble
          .scanForDevices(withServices: [], scanMode: ScanMode.lowLatency)
          .listen(
            (device) {
              if (generation != _generation) return;
              final name = device.name.toUpperCase().replaceAll(
                RegExp(r'[^A-Z0-9]'),
                '',
              );
              if (!name.contains('SBF70') && device.id != profile.deviceId) {
                return;
              }
              devices[device.id] = device;
              _notify();
              if (automatic &&
                  device.id == profile.deviceId &&
                  phase == ConnectionPhase.scanning) {
                unawaited(connect(profile, device));
              }
            },
            onError: (Object e) {
              if (generation == _generation) {
                unawaited(
                  _fail(
                    'Bluetooth-Suche fehlgeschlagen. Bitte Bluetooth prüfen und erneut suchen.',
                    e,
                  ),
                );
              }
            },
          );
      _timeout = Timer(const Duration(seconds: 25), () {
        unawaited(_scan?.cancel());
        _scan = null;
        if (generation == _generation) {
          _state(
            ConnectionPhase.idle,
            devices.isEmpty
                ? 'Keine Waage gefunden. Waage aktivieren und Sanitas-App schließen, dann erneut suchen.'
                : 'Wähle deine Waage aus der Liste.',
          );
        }
      });
    } catch (e) {
      if (generation == _generation) {
        await _fail(
          'Bluetooth konnte nicht gestartet werden. Bitte erneut versuchen.',
          e,
        );
      }
    }
  }

  Future<void> connect(Profile profile, DiscoveredDevice device) async {
    if (phase == ConnectionPhase.connecting ||
        phase == ConnectionPhase.synchronizing ||
        phase == ConnectionPhase.ready) {
      return;
    }
    _state(ConnectionPhase.connecting, 'Verbindung zur Waage wird aufgebaut …');
    await disconnect(quiet: true);
    final generation = _generation;
    final protocol = SanitasProtocol(profile);
    final target = QualifiedCharacteristic(
      deviceId: device.id,
      serviceId: service,
      characteristicId: characteristic,
    );
    connectedName = device.name.isEmpty ? 'Sanitas SBF 70' : device.name;
    _state(ConnectionPhase.connecting, 'Verbindung zur Waage wird aufgebaut …');
    void deadline() {
      _timeout?.cancel();
      _timeout = Timer(const Duration(seconds: 15), () {
        if (generation == _generation && phase != ConnectionPhase.ready) {
          unawaited(
            _fail(
              'Die Waage antwortet nicht. Aktiviere sie erneut und schließe andere Waagen-Apps.',
            ),
          );
        }
      });
    }

    Future<void> events(List<ScaleEvent> events) async {
      for (final event in events) {
        if (generation != _generation) return;
        switch (event) {
          case SendFrame():
            _log('TX ${hexBytes(event.bytes)}');
            await _ble
                .writeCharacteristicWithResponse(target, value: event.bytes)
                .timeout(const Duration(seconds: 6));
          case ScaleMessage():
            if (event.error) {
              await _fail(event.text);
              return;
            }
            message = event.text;
            _notify();
          case ScaleBound():
            await onBound(profile, device.id, connectedName!, event.remoteId);
          case ScaleReady():
            _timeout?.cancel();
            phase = ConnectionPhase.ready;
            _notify();
          case ScaleBattery():
            battery = event.percent;
            _notify();
          case ScaleLiveWeight():
            liveWeight = event.kg;
            _notify();
          case ScaleReading():
            await onReading(event.measurement);
            liveWeight = event.measurement.weight;
            message = 'Messung gespeichert. Dein Verlauf ist aktuell.';
            _notify();
        }
      }
    }

    void enqueue(Future<void> Function() action) {
      _queue = _queue
          .then((_) async {
            if (generation == _generation) await action();
          })
          .catchError((Object e) async {
            if (generation == _generation) {
              await _fail(
                'Verbindung unterbrochen oder Daten konnten nicht gespeichert werden. Bitte erneut verbinden.',
                e,
              );
            }
          });
    }

    deadline();
    _link = _ble
        .connectToDevice(
          id: device.id,
          connectionTimeout: const Duration(seconds: 12),
          servicesWithCharacteristicsToDiscover: {
            service: [characteristic],
          },
        )
        .listen(
          (update) {
            if (generation != _generation) return;
            if (update.connectionState == DeviceConnectionState.connected) {
              _state(
                ConnectionPhase.synchronizing,
                'Profil und gespeicherte Messungen werden abgeglichen …',
              );
              _notifications = _ble
                  .subscribeToCharacteristic(target)
                  .listen(
                    (bytes) {
                      if (generation != _generation) return;
                      _log('RX ${hexBytes(bytes)}');
                      enqueue(() async {
                        await events(protocol.receive(bytes));
                        if (phase == ConnectionPhase.synchronizing) deadline();
                      });
                    },
                    onError: (Object e) {
                      if (generation == _generation) {
                        unawaited(
                          _fail(
                            'Die Waage stellt den erwarteten SBF-70-Dienst nicht bereit. Bitte Diagnose exportieren.',
                            e,
                          ),
                        );
                      }
                    },
                  );
              enqueue(() async {
                // Let CCCD subscription finish before sending the proprietary handshake.
                await Future<void>.delayed(const Duration(milliseconds: 600));
                await events(protocol.start());
              });
            } else if (update.connectionState ==
                DeviceConnectionState.disconnected) {
              _timeout?.cancel();
              unawaited(
                disconnect(quiet: true).then((_) {
                  if (phase != ConnectionPhase.error) {
                    _state(
                      ConnectionPhase.idle,
                      'Waage getrennt. Zum nächsten Wiegen erneut verbinden.',
                    );
                  }
                }),
              );
            }
          },
          onError: (Object e) {
            if (generation == _generation) {
              unawaited(
                _fail(
                  'Verbindung fehlgeschlagen. Waage aufwecken und erneut versuchen.',
                  e,
                ),
              );
            }
          },
        );
  }

  Future<void> _fail(String text, [Object? error]) async {
    if (error != null) _log('ERROR $error');
    await disconnect(quiet: true);
    _state(ConnectionPhase.error, text);
  }

  Future<void> disconnect({bool quiet = false}) async {
    _generation++;
    _timeout?.cancel();
    _timeout = null;
    final scan = _scan, link = _link, notifications = _notifications;
    _scan = null;
    _link = null;
    _notifications = null;
    await notifications?.cancel();
    await scan?.cancel();
    await link?.cancel();
    if (!quiet) {
      _state(ConnectionPhase.idle, 'Verbindung beendet.');
    } else {
      phase = ConnectionPhase.idle;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(disconnect(quiet: true));
    super.dispose();
  }
}
