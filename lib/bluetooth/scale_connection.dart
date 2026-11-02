import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';

import '../domain/models.dart';
import 'ble_transport.dart';
import 'sanitas_protocol.dart';

enum ConnectionPhase {
  idle,
  checking,
  scanning,
  connecting,
  subscribing,
  retrying,
  ready,
  error,
}

enum ReceptionPhase {
  waiting,
  weighing,
  receiving,
  received,
  saving,
  saved,
  duplicate,
  discarded,
}

/// Each attempt owns its streams, timers and queue. Old callbacks cannot update
/// the UI, write to a new GATT link, or schedule another retry.
class _Session {
  Profile profile;
  final DiscoveredDevice? device;
  final int attempt;
  _Session(this.profile, {this.device, this.attempt = 1});
  StreamSubscription<DiscoveredDevice>? scan;
  StreamSubscription<ConnectionStateUpdate>? link;
  StreamSubscription<List<int>>? notifications;
  StreamSubscription<BleStatus>? status;
  Timer? deadline, progressTimer, handshake, retry, measurement;
  Future<void> queue = Future.value();
  bool connecting = false, connected = false, preparing = false;
  int pending = 0;
  SanitasProtocol? protocol;
  void cancelTimers() {
    deadline?.cancel();
    progressTimer?.cancel();
    handshake?.cancel();
    retry?.cancel();
    measurement?.cancel();
  }
}

class ScaleConnection extends ChangeNotifier {
  final BleTransport _ble;
  final Future<bool> Function(Measurement) onReading;
  final Future<void> Function(Profile, String, String) onBound;
  ScaleConnection({
    required this.onReading,
    required this.onBound,
    BleTransport? transport,
  }) : _ble = transport ?? AndroidBleTransport();
  ConnectionPhase phase = ConnectionPhase.idle;
  String message = 'Verbinde deine Waage für die erste Messung.';
  String? connectedName;
  int? battery;
  double? liveWeight;
  final liveValues = <Metric, double>{};
  ReceptionPhase reception = ReceptionPhase.waiting;
  void _resetReception() {
    liveWeight = null;
    liveValues.clear();
    reception = ReceptionPhase.waiting;
  }

  final devices = <String, DiscoveredDevice>{};
  final List<String> diagnosticLog = [];
  _Session? _session;
  Future<void> _cleanup = Future.value();
  Future<void> _persistence = Future.value();
  bool _disposed = false, _manuallyStopped = false, _background = false;
  bool get busy =>
      phase != ConnectionPhase.idle && phase != ConnectionPhase.error;
  bool get working => busy && phase != ConnectionPhase.ready;
  bool _current(_Session s) => !_disposed && identical(s, _session);
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

  Future<void> _cancel(StreamSubscription<dynamic>? subscription) async {
    if (subscription == null) return;
    try {
      await subscription.cancel().timeout(const Duration(seconds: 3));
    } catch (e) {
      _log('CLEANUP $e');
    }
  }

  void _replace(_Session? next) {
    final old = _session;
    _session = next; // Invalidate synchronously, before the first await.
    old?.cancelTimers();
    if (old != null) {
      _cleanup = _cleanup.then((_) async {
        await Future.wait([
          _cancel(old.notifications),
          _cancel(old.scan),
          _cancel(old.link),
          _cancel(old.status),
        ]);
      });
    }
  }

  Future<void> scan(Profile profile, {bool automatic = false}) async {
    if (_disposed || busy || _background || (automatic && _manuallyStopped)) {
      return;
    }
    if (!automatic) _manuallyStopped = false;
    final s = _Session(profile);
    _replace(s);
    devices.clear();
    _resetReception();
    battery = null;
    connectedName = null;
    _state(ConnectionPhase.checking, 'Bluetooth wird vorbereitet …');
    await _start(s, requestPermission: !automatic, automatic: automatic);
  }

  Future<void> connect(Profile profile, DiscoveredDevice device) async {
    if (_disposed ||
        _background ||
        (busy && phase != ConnectionPhase.scanning)) {
      return;
    }
    _manuallyStopped = false;
    final s = _Session(profile, device: device);
    _replace(s);
    _resetReception();
    battery = null;
    connectedName = device.name.isEmpty ? 'Sanitas SBF 70' : device.name;
    _state(ConnectionPhase.connecting, 'Verbindung zur Waage wird aufgebaut …');
    await _start(s, requestPermission: true);
  }

  Future<void> _start(
    _Session s, {
    required bool requestPermission,
    bool automatic = false,
  }) async {
    try {
      await _cleanup;
      await _persistence;
      if (!_current(s)) return;
      s.preparing = requestPermission;
      await _ble
          .prepare(requestPermission: requestPermission)
          .timeout(const Duration(seconds: 60));
      if (!_current(s)) return;
      s.preparing = false;
      if (_background) {
        await disconnect(quiet: true);
        return;
      }
      s.status = _ble.status.listen(
        (status) {
          if (_current(s) &&
              status != BleStatus.ready &&
              status != BleStatus.unknown) {
            _fail(s, bluetoothStatusMessage(status), retry: false);
          }
        },
        onError: (Object e) => _fail(
          s,
          'Bluetooth-Status konnte nicht gelesen werden.',
          error: e,
          retry: false,
        ),
      );
      if (!_current(s)) return;
      if (s.device == null || s.attempt > 1) {
        _search(s, automatic: automatic || s.device != null);
      } else {
        _openLink(s);
      }
    } on BluetoothUnavailable catch (e) {
      _fail(s, e.message, retry: false);
    } catch (e) {
      _fail(
        s,
        'Bluetooth konnte nicht gestartet werden. Bitte erneut suchen.',
        error: e,
      );
    }
  }

  void _search(_Session s, {required bool automatic}) {
    _state(
      ConnectionPhase.scanning,
      s.attempt > 1
          ? 'Suche erneut nach deiner Waage (${s.attempt}/3). Bitte kurz antippen …'
          : 'Tippe die Waage kurz an. Suche nach Sanitas SBF 70 …',
    );
    s.scan = _ble.scan().listen(
      (device) {
        if (!_current(s) || s.connecting) return;
        final name = device.name.toUpperCase().replaceAll(
          RegExp(r'[^A-Z0-9]'),
          '',
        );
        final targetId = s.device?.id ?? s.profile.deviceId;
        if (!name.contains('SBF70') &&
            device.id != targetId &&
            !device.serviceUuids.contains(scaleService)) {
          return;
        }
        devices[device.id] = device;
        _notify();
        if (automatic && device.id == targetId) {
          if (s.device == null) {
            unawaited(connect(s.profile, device));
          } else {
            s.connecting = true;
            s.deadline?.cancel();
            final scan = s.scan;
            unawaited(
              _cancel(scan).then((_) {
                if (!_current(s)) return;
                s.scan = null;
                try {
                  _openLink(s);
                } catch (e) {
                  _fail(s, 'Verbindung zur Waage fehlgeschlagen.', error: e);
                }
              }),
            );
          }
        }
      },
      onError: (Object e) => _fail(
        s,
        'Bluetooth-Suche fehlgeschlagen. Bitte Bluetooth prüfen.',
        error: e,
      ),
      onDone: () {
        if (_current(s) && !s.connecting) {
          _fail(s, 'Bluetooth-Suche wurde unterbrochen. Bitte erneut suchen.');
        }
      },
    );
    s.deadline = Timer(Duration(seconds: s.device == null ? 25 : 10), () {
      if (!_current(s)) return;
      if (s.device != null) {
        _fail(
          s,
          'Die Waage ist nicht erreichbar. Bitte aufwecken und erneut suchen.',
        );
      } else {
        _replace(null);
        _state(
          ConnectionPhase.idle,
          devices.isEmpty
              ? 'Keine Waage gefunden. Waage aktivieren und Sanitas-App schließen, dann erneut suchen.'
              : 'Wähle deine Waage aus der Liste.',
        );
      }
    });
  }

  void _openLink(_Session s) {
    if (!_current(s)) return;
    s.connecting = true;
    s.protocol = SanitasProtocol(
      s.profile.withDevice(s.device!.id, s.device!.name),
    );
    _state(
      ConnectionPhase.connecting,
      'Verbindung zur Waage wird aufgebaut (${s.attempt}/3) …',
    );
    // Fixed outer limit: junk or repeated notifications cannot keep setup alive.
    s.deadline = Timer(
      const Duration(seconds: 90),
      () => _fail(
        s,
        'Die Anmeldung dauert zu lange. Die Verbindung wird neu aufgebaut.',
      ),
    );
    _progressDeadline(s);
    s.link = _ble
        .connect(s.device!.id)
        .listen(
          (update) {
            if (!_current(s) || update.deviceId != s.device!.id) return;
            _log('LINK ${update.connectionState.name} ${update.failure ?? ''}');
            if (update.connectionState == DeviceConnectionState.connected &&
                !s.connected) {
              s.connected = true;
              _progressDeadline(s);
              _state(
                ConnectionPhase.subscribing,
                'Bluetooth-Empfang wird eingerichtet …',
              );
              _enqueue(s, () => _subscribe(s));
            } else if (update.connectionState ==
                DeviceConnectionState.disconnected) {
              _fail(s, 'Die Verbindung zur Waage wurde unterbrochen.');
            }
          },
          onError: (Object e) =>
              _fail(s, 'Verbindung zur Waage fehlgeschlagen.', error: e),
          onDone: () => _fail(s, 'Die Verbindung zur Waage wurde beendet.'),
        );
  }

  void _progressDeadline(_Session s) {
    s.progressTimer?.cancel();
    s.progressTimer = Timer(
      const Duration(seconds: 15),
      () => _fail(
        s,
        'Die Waage antwortet nicht. Bitte aufwecken und andere Waagen-Apps schließen.',
      ),
    );
  }

  Future<void> _subscribe(_Session s) async {
    _log('GATT discovery');
    try {
      await _ble.validate(s.device!.id).timeout(const Duration(seconds: 12));
    } on BluetoothUnavailable {
      rethrow;
    } catch (e) {
      _fail(
        s,
        'Bluetooth-Dienst der Waage konnte nicht eingerichtet werden. Bitte Sanitas-App schließen und Waage neu aufwecken.',
        error: e,
      );
      return;
    }
    if (!_current(s)) return;
    s.notifications = _ble
        .notifications(s.device!.id)
        .listen(
          (bytes) {
            if (!_current(s)) return;
            final frame = List<int>.of(bytes);
            final receivedAt = DateTime.now();
            _log('RX ${hexBytes(frame)}');
            _enqueue(s, () async {
              final protocol = s.protocol!;
              final before = protocol.progress;
              final partial = protocol.hasPartialLive;
              final events = protocol.receive(frame, receivedAt: receivedAt);
              if (!protocol.hasPartialLive) {
                s.measurement?.cancel();
                s.measurement = null;
              } else if (!partial) {
                s.measurement = Timer(const Duration(seconds: 15), () {
                  if (_current(s)) {
                    _enqueue(s, () => _events(s, protocol.discardPartial()));
                  }
                });
              }
              if (protocol.phase != 'init') s.handshake?.cancel();
              await _events(s, events);
              if (_current(s) &&
                  phase == ConnectionPhase.subscribing &&
                  before != protocol.progress) {
                _progressDeadline(s);
              }
            });
          },
          onError: (Object e) =>
              _fail(s, 'Bluetooth-Datenübertragung unterbrochen.', error: e),
          onDone: () =>
              _fail(s, 'Die Waage sendet keine Bluetooth-Daten mehr.'),
        );
    // No CCCD-ready callback in the plugin. Allow setup time, then retry ONLY
    // the idempotent handshake if its reply was lost, never profile writes.
    await Future<void>.delayed(const Duration(milliseconds: 600));
    if (!_current(s)) return;
    await _events(s, s.protocol!.start());
    if (!_current(s)) return;
    var retries = 0;
    s.handshake = Timer.periodic(const Duration(seconds: 3), (timer) {
      if (!_current(s) || s.protocol!.phase != 'init' || retries >= 2) {
        timer.cancel();
        return;
      }
      retries++;
      _enqueue(s, () async {
        if (s.protocol!.phase == 'init') await _events(s, s.protocol!.start());
      });
    });
  }

  void _enqueue(_Session s, Future<void> Function() action) {
    if (!_current(s)) return;
    if (++s.pending > 256) {
      _fail(
        s,
        'Die Waage sendet zu viele Daten auf einmal. Bitte erneut verbinden.',
        retry: false,
      );
      return;
    }
    s.queue = s.queue.then((_) async {
      try {
        if (_current(s)) await action();
      } on BluetoothUnavailable catch (e) {
        _fail(s, e.message, retry: false);
      } catch (e) {
        _fail(s, 'Bluetooth-Übertragung fehlgeschlagen.', error: e);
      } finally {
        s.pending--;
      }
    });
  }

  Future<void> _persist(_Session s, Future<void> Function() action) async {
    final operation = action();
    // Profile edits wait for already accepted data to finish saving.
    _persistence = operation.catchError((Object _) {});
    try {
      await operation;
    } catch (e) {
      _fail(
        s,
        'Daten konnten nicht gespeichert werden. Bitte erneut verbinden; der Waagenspeicher bleibt unverändert.',
        error: e,
        retry: false,
      );
    }
  }

  Future<void> _events(_Session s, List<ScaleEvent> events) async {
    for (final event in events) {
      if (!_current(s)) return;
      switch (event) {
        case SendFrame():
          _log('TX ${hexBytes(event.bytes)}');
          try {
            await _ble
                .write(s.device!.id, event.bytes)
                .timeout(const Duration(seconds: 6));
          } catch (e) {
            _fail(
              s,
              event.bytes.first == 0xe6
                  ? 'Bluetooth-Anmeldung fehlgeschlagen. Waage aufwecken und Sanitas-App schließen.'
                  : 'Empfangsbestätigung fehlgeschlagen. Bitte erneut verbinden.',
              error: e,
            );
            return;
          }
        case ScaleMessage():
          if (event.error) {
            _fail(s, event.text, retry: event.retryable);
            return;
          }
          message = event.text;
          _notify();
        case ScaleReady():
          await _persist(
            s,
            () => onBound(s.profile, s.device!.id, connectedName!),
          );
          if (!_current(s)) return;
          s.deadline?.cancel();
          s.progressTimer?.cancel();
          s.handshake?.cancel();
          _state(
            ConnectionPhase.ready,
            'Verbunden. Jetzt an der Waage wiegen; warte auf Messwerte.',
          );
        case ScaleBattery():
          battery = event.percent;
          _notify();
        case ScaleTransfer():
          liveValues
            ..clear()
            ..addAll(event.values);
          liveWeight = liveValues[Metric.weight];
          reception = event.packet == 0
              ? ReceptionPhase.discarded
              : event.packet == 3
              ? ReceptionPhase.received
              : ReceptionPhase.receiving;
          _notify();
        case ScaleLiveWeight():
          if (reception != ReceptionPhase.weighing &&
              reception != ReceptionPhase.receiving) {
            _resetReception();
          }
          if (reception != ReceptionPhase.receiving) {
            reception = ReceptionPhase.weighing;
          }
          liveValues[Metric.weight] = event.kg;
          liveWeight = event.kg;
          _notify();
        case ScaleReading():
          liveValues
            ..clear()
            ..addAll(event.measurement.values);
          reception = ReceptionPhase.saving;
          _notify();
          var inserted = false;
          await _persist(s, () async {
            inserted = await onReading(event.measurement);
          });
          if (!_current(s)) return;
          reception = inserted
              ? ReceptionPhase.saved
              : ReceptionPhase.duplicate;
          liveWeight = event.measurement.weight;
          message = inserted
              ? 'Messung gespeichert. Dein Verlauf ist aktuell.'
              : 'Messung bereits verarbeitet. Dein Verlauf ist aktuell.';
          _notify();
      }
    }
  }

  void _fail(_Session s, String text, {Object? error, bool retry = true}) {
    if (!_current(s)) return;
    _log('ATTEMPT ${s.attempt} $text ${error ?? ''}');
    if (retry && s.device != null && s.attempt < 3 && !_background) {
      final next = _Session(
        s.profile,
        device: s.device,
        attempt: s.attempt + 1,
      );
      _replace(next);
      _resetReception();
      battery = null;
      _state(
        ConnectionPhase.retrying,
        '$text Neuer Versuch ${next.attempt}/3 – bitte Waage kurz antippen.',
      );
      next.retry = Timer(Duration(seconds: s.attempt * 2), () {
        if (_current(next)) unawaited(_start(next, requestPermission: false));
      });
    } else {
      _replace(null);
      _resetReception();
      battery = null;
      _state(
        ConnectionPhase.error,
        s.attempt >= 3 && retry
            ? '$text Drei Versuche beendet. Bitte Waage aufwecken und erneut suchen.'
            : text,
      );
    }
  }

  Future<void> disconnect({bool quiet = false}) async {
    if (!quiet) _manuallyStopped = true;
    _replace(null);
    _resetReception();
    battery = null;
    _state(
      ConnectionPhase.idle,
      quiet ? 'Waage getrennt.' : 'Verbindung beendet.',
    );
    await _cleanup;
    await _persistence;
  }

  Future<void> pause() async {
    _background = true;
    // A native permission dialog may temporarily pause the activity. Its result
    // is consumed only if the app has resumed when prepare finishes.
    if (_session?.preparing == true) return;
    await disconnect(quiet: true);
  }

  void resume() {
    _background = false;
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(disconnect(quiet: true));
    super.dispose();
  }
}
