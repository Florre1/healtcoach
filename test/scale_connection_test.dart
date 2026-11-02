import 'dart:async';
import 'dart:typed_data';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthcoach/bluetooth/ble_transport.dart';
import 'package:healthcoach/bluetooth/scale_connection.dart';
import 'package:healthcoach/bluetooth/sanitas_protocol.dart';
import 'package:healthcoach/domain/models.dart';

import 'fixtures.dart';

final device = DiscoveredDevice(
  id: 'AA:BB',
  name: 'SANITAS SBF70',
  serviceData: {},
  manufacturerData: Uint8List(0),
  serviceUuids: [],
  rssi: -50,
);

class FakeBle implements BleTransport {
  final adapter = StreamController<BleStatus>.broadcast();
  final scans = <StreamController<DiscoveredDevice>>[];
  final links = <StreamController<ConnectionStateUpdate>>[];
  final receivers = <StreamController<List<int>>>[];
  final writes = <List<int>>[];
  final requests = <bool>[];
  Completer<void>? permission, validation, writeGate, cancelGate;
  Object? permissionError, validationError;
  int activeWrites = 0, maxWrites = 0;
  @override
  Future<void> prepare({required bool requestPermission}) async {
    requests.add(requestPermission);
    if (permissionError != null) throw permissionError!;
    await permission?.future;
  }

  @override
  Stream<BleStatus> get status => adapter.stream;
  @override
  Stream<DiscoveredDevice> scan() {
    final controller = StreamController<DiscoveredDevice>();
    scans.add(controller);
    return controller.stream;
  }

  @override
  Stream<ConnectionStateUpdate> connect(String id) {
    final gate = cancelGate;
    final controller = StreamController<ConnectionStateUpdate>(
      onCancel: () async {
        await gate?.future;
      },
    );
    links.add(controller);
    return controller.stream;
  }

  @override
  Future<void> validate(String id) async {
    if (validationError != null) throw validationError!;
    await validation?.future;
  }

  @override
  Stream<List<int>> notifications(String id) {
    final controller = StreamController<List<int>>();
    receivers.add(controller);
    return controller.stream;
  }

  @override
  Future<void> write(String id, List<int> bytes) async {
    writes.add(List.of(bytes));
    activeWrites++;
    if (activeWrites > maxWrites) maxWrites = activeWrites;
    try {
      await writeGate?.future;
    } finally {
      activeWrites--;
    }
  }

  void update(DeviceConnectionState state) => links.last.add(
    ConnectionStateUpdate(
      deviceId: device.id,
      connectionState: state,
      failure: null,
    ),
  );
}

void main() {
  late FakeBle ble;
  late ScaleConnection scale;
  late List<Measurement> readings;
  late List<String> bindings;
  void setup({
    Future<bool> Function(Measurement)? save,
    Future<void> Function(Profile, String, String)? bind,
  }) {
    ble = FakeBle();
    readings = [];
    bindings = [];
    scale = ScaleConnection(
      transport: ble,
      onReading:
          save ??
          (m) async {
            readings.add(m);
            return true;
          },
      onBound:
          bind ??
          (p, id, name) async {
            bindings.add(id);
          },
    );
  }

  void open(FakeAsync time) {
    unawaited(scale.connect(testProfile(), device));
    time.flushMicrotasks();
    ble.update(DeviceConnectionState.connected);
    time.flushMicrotasks();
    time.elapse(const Duration(milliseconds: 600));
  }

  void receive(FakeAsync time, List<int> bytes) {
    ble.receivers.last.add(bytes);
    time.flushMicrotasks();
  }

  void ready(FakeAsync time) {
    for (final reply in sessionReplies) {
      receive(time, reply);
    }
    expect(scale.phase, ConnectionPhase.ready);
  }

  void measure(FakeAsync time) {
    receive(time, [0xe7, 0x59, 3, 1, 1, ...idBytes('0000000000000065')]);
    receive(time, [0xe7, 0x59, 3, 2, ...measurementPacket().take(11)]);
    receive(time, [0xe7, 0x59, 3, 3, ...measurementPacket().skip(11)]);
  }

  void finish(FakeAsync time) {
    scale.dispose();
    time.flushMicrotasks();
  }

  test(
    'body preview follows packets and all nine values are saved together',
    () => fakeAsync((time) {
      final saved = Completer<bool>();
      Measurement? stored;
      setup(
        save: (m) {
          stored = m;
          return saved.future;
        },
      );
      open(time);
      ready(time);
      receive(time, [0xe7, 0x58, 1, 6, 64]);
      expect(scale.liveValues, {Metric.weight: 80});
      receive(time, [0xe7, 0x59, 3, 1, 1, ...idBytes('0000000000000099')]);
      expect(scale.liveValues, isEmpty);
      receive(time, [0xe7, 0x59, 3, 2, ...measurementPacket().take(11)]);
      expect(scale.liveValues.keys.toSet(), {
        Metric.weight,
        Metric.fat,
        Metric.impedance,
      });
      expect(scale.liveValues[Metric.fat], 21.5);
      expect(scale.liveValues.containsKey(Metric.water), isFalse);
      expect(stored, isNull);
      receive(time, [0xe7, 0x59, 3, 3, ...measurementPacket().skip(11)]);
      expect(scale.liveValues.keys.toSet(), Metric.values.toSet());
      expect(scale.liveValues[Metric.water], 57.2);
      expect(scale.liveValues[Metric.amr], 2670);
      expect(stored!.values, scale.liveValues);
      expect(stored!.profileId, testProfile().id);
      expect(scale.reception, ReceptionPhase.saving);
      saved.complete(true);
      time.flushMicrotasks();
      expect(scale.reception, ReceptionPhase.saved);
      receive(time, [0xe7, 0x58, 1, 6, 65]);
      expect(scale.liveValues.keys, [Metric.weight]);
      unawaited(scale.disconnect());
      time.flushMicrotasks();
      expect(scale.liveValues, isEmpty);
      finish(time);
    }),
  );
  test(
    'timed out body preview is cleared and never persisted',
    () => fakeAsync((time) {
      setup();
      open(time);
      ready(time);
      receive(time, [0xe7, 0x59, 3, 1, 1, ...idBytes('0000000000000099')]);
      receive(time, [0xe7, 0x59, 3, 2, ...measurementPacket().take(11)]);
      expect(scale.liveValues, isNotEmpty);
      time.elapse(const Duration(seconds: 15));
      expect(scale.liveValues, isEmpty);
      expect(scale.reception, ReceptionPhase.discarded);
      expect(readings, isEmpty);
      expect(scale.phase, ConnectionPhase.ready);
      finish(time);
    }),
  );
  test(
    'permission dialog pause/resume keeps the original search',
    () => fakeAsync((time) {
      setup();
      ble.permission = Completer<void>();
      unawaited(scale.scan(testProfile()));
      time.flushMicrotasks();
      unawaited(scale.pause());
      time.flushMicrotasks();
      scale.resume();
      unawaited(scale.scan(testProfile(), automatic: true));
      ble.permission!.complete();
      time.flushMicrotasks();
      expect(ble.requests, [true]);
      expect(ble.scans, hasLength(1));
      expect(scale.phase, ConnectionPhase.scanning);
      finish(time);
    }),
  );
  test(
    'permission granted while app stays backgrounded does not start radio work',
    () => fakeAsync((time) {
      setup();
      ble.permission = Completer<void>();
      unawaited(scale.scan(testProfile()));
      time.flushMicrotasks();
      unawaited(scale.pause());
      time.flushMicrotasks();
      ble.permission!.complete();
      time.flushMicrotasks();
      expect(ble.scans, isEmpty);
      expect(scale.phase, ConnectionPhase.idle);
      finish(time);
    }),
  );
  test(
    'unfinished measurement is discarded without dropping the connection',
    () => fakeAsync((time) {
      setup();
      open(time);
      ready(time);
      receive(time, [0xe7, 0x59, 3, 1, 1, ...idBytes('0000000000000065')]);
      receive(time, [0xe7, 0x59, 3, 2, ...measurementPacket().take(11)]);
      time.elapse(const Duration(seconds: 15));
      expect(scale.phase, ConnectionPhase.ready);
      expect(readings, isEmpty);
      finish(time);
    }),
  );
  test(
    'complete live measurement cancels its partial-packet deadline',
    () => fakeAsync((time) {
      setup();
      open(time);
      ready(time);
      measure(time);
      time.elapse(const Duration(seconds: 30));
      expect(scale.phase, ConnectionPhase.ready);
      expect(readings, hasLength(1));
      finish(time);
    }),
  );
  test(
    'write timeout closes attempt and a fresh queue can reconnect',
    () => fakeAsync((time) {
      setup();
      final write = ble.writeGate = Completer<void>();
      open(time);
      time.elapse(const Duration(seconds: 6));
      expect(scale.phase, ConnectionPhase.retrying);
      ble.writeGate = null;
      time.elapse(const Duration(seconds: 2));
      ble.scans.last.add(device);
      time.flushMicrotasks();
      ble.update(DeviceConnectionState.connected);
      time.flushMicrotasks();
      time.elapse(const Duration(milliseconds: 600));
      ready(time);
      write.complete();
      time.flushMicrotasks();
      expect(scale.phase, ConnectionPhase.ready);
      finish(time);
    }),
  );
  test(
    'automatic scan ignores unrelated scales and finds saved id without a name',
    () => fakeAsync((time) {
      setup();
      unawaited(
        scale.scan(
          testProfile().withDevice(device.id, device.name),
          automatic: true,
        ),
      );
      time.flushMicrotasks();
      ble.scans.last.add(
        DiscoveredDevice(
          id: 'different',
          name: 'SANITAS SBF70',
          serviceData: {},
          manufacturerData: Uint8List(0),
          serviceUuids: [],
          rssi: -40,
        ),
      );
      time.flushMicrotasks();
      expect(ble.links, isEmpty);
      ble.scans.last.add(
        DiscoveredDevice(
          id: device.id,
          name: '',
          serviceData: {},
          manufacturerData: Uint8List(0),
          serviceUuids: [],
          rssi: -40,
        ),
      );
      time.flushMicrotasks();
      expect(ble.links, hasLength(1));
      ble.update(DeviceConnectionState.connected);
      time.flushMicrotasks();
      time.elapse(const Duration(milliseconds: 600));
      ready(time);
      time.elapse(const Duration(seconds: 25));
      expect(scale.phase, ConnectionPhase.ready);
      finish(time);
    }),
  );

  test(
    'double tap during permission prompt starts only one search',
    () => fakeAsync((time) {
      setup();
      ble.permission = Completer<void>();
      unawaited(scale.scan(testProfile()));
      unawaited(scale.scan(testProfile()));
      time.flushMicrotasks();
      expect(scale.phase, ConnectionPhase.checking);
      expect(ble.requests, [true]);
      ble.permission!.complete();
      time.flushMicrotasks();
      expect(ble.scans, hasLength(1));
      finish(time);
    }),
  );
  test(
    'cancelled permission result cannot resurrect a search',
    () => fakeAsync((time) {
      setup();
      ble.permission = Completer<void>();
      unawaited(scale.scan(testProfile()));
      time.flushMicrotasks();
      unawaited(scale.disconnect());
      time.flushMicrotasks();
      ble.permission!.completeError(StateError('old permission error'));
      time.flushMicrotasks();
      expect(scale.phase, ConnectionPhase.idle);
      expect(scale.message, 'Verbindung beendet.');
      expect(ble.scans, isEmpty);
      finish(time);
    }),
  );
  test(
    'late permission error does not overwrite a new attempt',
    () => fakeAsync((time) {
      setup();
      final old = ble.permission = Completer<void>();
      unawaited(scale.scan(testProfile()));
      time.flushMicrotasks();
      unawaited(scale.disconnect());
      time.flushMicrotasks();
      ble.permission = null;
      unawaited(scale.scan(testProfile()));
      time.flushMicrotasks();
      old.completeError(StateError('stale'));
      time.flushMicrotasks();
      expect(scale.phase, ConnectionPhase.scanning);
      expect(ble.scans, hasLength(1));
      finish(time);
    }),
  );
  test(
    'double connect and repeated connected events subscribe only once',
    () => fakeAsync((time) {
      setup();
      open(time);
      unawaited(scale.connect(testProfile(), device));
      ble.update(DeviceConnectionState.connected);
      time.flushMicrotasks();
      expect(ble.links, hasLength(1));
      expect(ble.receivers, hasLength(1));
      expect(ble.writes, [
        [0xe6, 1],
      ]);
      ready(time);
      expect(ble.maxWrites, 1);
      finish(time);
    }),
  );
  test(
    'disconnect during discovery sends no handshake',
    () => fakeAsync((time) {
      setup();
      ble.validation = Completer<void>();
      open(time);
      unawaited(scale.disconnect());
      time.flushMicrotasks();
      ble.validation!.complete();
      time.flushMicrotasks();
      time.elapse(const Duration(seconds: 1));
      expect(ble.receivers, isEmpty);
      expect(ble.writes, isEmpty);
      expect(scale.phase, ConnectionPhase.idle);
      finish(time);
    }),
  );
  test(
    'lost handshake is retried twice; junk does not extend the deadline',
    () => fakeAsync((time) {
      setup();
      open(time);
      for (var i = 0; i < 14; i++) {
        receive(time, [0, 99, 1]);
        time.elapse(const Duration(seconds: 1));
      }
      expect(ble.writes, [
        [0xe6, 1],
        [0xe6, 1],
        [0xe6, 1],
      ]);
      time.elapse(const Duration(seconds: 1));
      expect(scale.phase, ConnectionPhase.retrying);
      finish(time);
    }),
  );
  test(
    'successful handshake cancels further handshake writes',
    () => fakeAsync((time) {
      setup();
      open(time);
      ready(time);
      time.elapse(const Duration(seconds: 100));
      expect(scale.phase, ConnectionPhase.ready);
      expect(ble.writes.where((b) => b[0] == 0xe6), hasLength(1));
      finish(time);
    }),
  );
  test(
    'disconnect retries with prescan and stops after three attempts',
    () => fakeAsync((time) {
      setup();
      open(time);
      for (var attempt = 1; attempt <= 3; attempt++) {
        ble.update(DeviceConnectionState.disconnected);
        time.flushMicrotasks();
        if (attempt < 3) {
          expect(scale.phase, ConnectionPhase.retrying);
          time.elapse(Duration(seconds: attempt * 2));
          expect(scale.phase, ConnectionPhase.scanning);
          ble.scans.last.add(device);
          time.flushMicrotasks();
          expect(ble.links, hasLength(attempt + 1));
          ble.update(DeviceConnectionState.connected);
          time.flushMicrotasks();
          time.elapse(const Duration(milliseconds: 600));
        }
      }
      expect(scale.phase, ConnectionPhase.error);
      time.elapse(const Duration(minutes: 2));
      expect(ble.links, hasLength(3));
      expect(ble.requests, [true, false, false]);
      finish(time);
    }),
  );
  test(
    'manual stop cancels retries and suppresses resume autoconnect',
    () => fakeAsync((time) {
      setup();
      open(time);
      ble.update(DeviceConnectionState.disconnected);
      time.flushMicrotasks();
      unawaited(scale.disconnect());
      time.flushMicrotasks();
      time.elapse(const Duration(minutes: 2));
      unawaited(
        scale.scan(
          testProfile().withDevice(device.id, device.name),
          automatic: true,
        ),
      );
      time.flushMicrotasks();
      expect(ble.links, hasLength(1));
      expect(ble.scans, isEmpty);
      unawaited(scale.scan(testProfile()));
      time.flushMicrotasks();
      expect(scale.phase, ConnectionPhase.scanning);
      finish(time);
    }),
  );
  test(
    'adapter powered off ends session without a retry loop',
    () => fakeAsync((time) {
      setup();
      open(time);
      ready(time);
      ble.adapter.add(BleStatus.poweredOff);
      time.flushMicrotasks();
      expect(scale.phase, ConnectionPhase.error);
      expect(scale.message, contains('Bluetooth am Handy'));
      expect(scale.battery, isNull);
      time.elapse(const Duration(minutes: 1));
      expect(ble.links, hasLength(1));
      finish(time);
    }),
  );
  test(
    'permanent permission and wrong GATT service failures do not retry',
    () => fakeAsync((time) {
      setup();
      ble.permissionError = const BluetoothUnavailable('Zugriff fehlt');
      unawaited(scale.connect(testProfile(), device));
      time.flushMicrotasks();
      expect(scale.message, 'Zugriff fehlt');
      expect(ble.links, isEmpty);
      ble.permissionError = null;
      ble.validationError = const BluetoothUnavailable('Falscher Dienst');
      open(time);
      expect(scale.message, 'Falscher Dienst');
      time.elapse(const Duration(minutes: 1));
      expect(ble.links, hasLength(1));
      finish(time);
    }),
  );
  test(
    'missing handshake never claims ready; rejection stops cleanly',
    () => fakeAsync((time) {
      setup();
      open(time);
      expect(scale.phase, ConnectionPhase.subscribing);
      receive(time, [0xe6, 1, 0x20]);
      expect(scale.phase, ConnectionPhase.error);
      finish(time);
    }),
  );
  test(
    'slow native cancellation cannot clobber a newer state',
    () => fakeAsync((time) {
      setup();
      final gate = ble.cancelGate = Completer<void>();
      open(time);
      unawaited(scale.disconnect());
      ble.cancelGate = null;
      unawaited(scale.scan(testProfile()));
      time.flushMicrotasks();
      expect(scale.phase, ConnectionPhase.checking);
      time.elapse(const Duration(seconds: 3));
      expect(scale.phase, ConnectionPhase.scanning);
      gate.complete();
      time.flushMicrotasks();
      expect(scale.phase, ConnectionPhase.scanning);
      finish(time);
    }),
  );
  test(
    'late write error cannot poison the new session queue',
    () => fakeAsync((time) {
      setup();
      final gate = ble.writeGate = Completer<void>();
      open(time);
      unawaited(scale.disconnect());
      time.flushMicrotasks();
      ble.writeGate = null;
      open(time);
      ready(time);
      gate.completeError(StateError('stale write'));
      time.flushMicrotasks();
      expect(scale.phase, ConnectionPhase.ready);
      finish(time);
    }),
  );
  test(
    'saved confirmation is shown only after the database completes',
    () => fakeAsync((time) {
      final saved = Completer<bool>();
      setup(save: (_) => saved.future);
      open(time);
      ready(time);
      measure(time);
      expect(scale.message, isNot(contains('Messung gespeichert')));
      saved.complete(true);
      time.flushMicrotasks();
      expect(scale.message, 'Messung gespeichert. Dein Verlauf ist aktuell.');
      finish(time);
    }),
  );
  test(
    'duplicate database result does not claim a newly saved reading',
    () => fakeAsync((time) {
      setup(save: (_) async => false);
      open(time);
      ready(time);
      measure(time);
      expect(scale.message, contains('bereits verarbeitet'));
      finish(time);
    }),
  );
  test(
    'database error stops retries and never claims a saved measurement',
    () => fakeAsync((time) {
      setup(save: (_) async => throw StateError('disk full'));
      open(time);
      ready(time);
      measure(time);
      expect(scale.phase, ConnectionPhase.error);
      expect(scale.message, contains('nicht gespeichert'));
      time.elapse(const Duration(minutes: 1));
      expect(ble.links, hasLength(1));
      finish(time);
    }),
  );
  test(
    'profile changes wait for in-flight binding persistence',
    () => fakeAsync((time) {
      final bound = Completer<void>();
      setup(bind: (_, _, _) => bound.future);
      open(time);
      for (final reply in sessionReplies) {
        receive(time, reply);
      }
      var disconnected = false;
      unawaited(
        scale.disconnect(quiet: true).then((_) {
          disconnected = true;
        }),
      );
      time.flushMicrotasks();
      expect(disconnected, isFalse);
      bound.complete();
      time.flushMicrotasks();
      expect(disconnected, isTrue);
      expect(ble.writes.any((b) => b.length > 1 && b[1] == 0x41), isFalse);
      expect(scale.phase, ConnectionPhase.idle);
      finish(time);
    }),
  );
  test(
    'ready message distinguishes body data from weight-only mode',
    () => fakeAsync((time) {
      setup();
      open(time);
      ready(time);
      expect(scale.bodyData, isTrue);
      expect(scale.message, 'Bereit. Steige barfuß auf die Waage.');
      expect(
        ble.writes.where((b) => b.length > 1 && b[1] == 0x40),
        hasLength(1),
      );
      unawaited(scale.disconnect());
      time.flushMicrotasks();
      open(time);
      receive(time, sessionReplies[0]);
      receive(time, sessionReplies[1]);
      receive(time, [0xe7, 0xf0, 0x33, 1, 0, 8]);
      expect(scale.phase, ConnectionPhase.ready);
      expect(scale.bodyData, isFalse);
      expect(scale.message, startsWith('Verbunden, nur Gewicht'));
      finish(time);
    }),
  );
  test(
    'backgrounding cancels an outstanding retry and resume permits a new search',
    () => fakeAsync((time) {
      setup();
      open(time);
      ble.update(DeviceConnectionState.disconnected);
      time.flushMicrotasks();
      unawaited(scale.pause());
      time.flushMicrotasks();
      time.elapse(const Duration(seconds: 10));
      expect(ble.scans, isEmpty);
      scale.resume();
      unawaited(
        scale.scan(
          testProfile().withDevice(device.id, device.name),
          automatic: true,
        ),
      );
      time.flushMicrotasks();
      expect(ble.scans, hasLength(1));
      finish(time);
    }),
  );
}
