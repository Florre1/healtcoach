// SPDX-License-Identifier: GPL-3.0-or-later
// Protocol implementation informed by openScale's BeurerSanitasHandler.
// Copyright (C) 2025 olie.xdev <olie.xdeveloper@googlemail.com>
// Dart implementation and stricter framing/profile checks: HealthCoach contributors, 2026.
// See THIRD_PARTY_NOTICES.md and LICENSE.
import 'dart:typed_data';

import '../domain/models.dart';

sealed class ScaleEvent {}

class SendFrame extends ScaleEvent {
  final List<int> bytes;
  SendFrame(this.bytes);
}

class ScaleMessage extends ScaleEvent {
  final String text;
  final bool error;
  final bool retryable;
  ScaleMessage(this.text, {this.error = false, this.retryable = false});
}

class ScaleBattery extends ScaleEvent {
  final int percent;
  ScaleBattery(this.percent);
}

class ScaleReady extends ScaleEvent {}

class ScaleReading extends ScaleEvent {
  final Measurement measurement;
  ScaleReading(this.measurement);
}

class ScaleLiveWeight extends ScaleEvent {
  final double kg;
  ScaleLiveWeight(this.kg);
}

/// Preview only. Persistence waits for the complete, validated reading.
class ScaleTransfer extends ScaleEvent {
  final int packet;
  final Map<Metric, double> values;
  ScaleTransfer(this.packet, this.values);
}

String hexBytes(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
List<int> idBytes(String id) => List.generate(
  8,
  (i) => int.parse(id.substring(i * 2, i * 2 + 2), radix: 16),
);

int u16(List<int> b, int offset) => (b[offset] << 8) | b[offset + 1];
List<int> timeBytes(DateTime date) => (ByteData(
  4,
)..setUint32(0, date.millisecondsSinceEpoch ~/ 1000)).buffer.asUint8List();

/// Receive-only session: no scale users, history, or measurement-start commands.
/// The user starts the measurement on the scale itself.
class SanitasProtocol {
  final Profile profile;
  final DateTime Function() now;
  String phase = 'init';
  List<int>? _livePart;
  DateTime? _liveStarted;
  final _liveFrames = <int, String>{};
  final _seen = <String>{};
  bool get hasPartialLive => _liveStarted != null;
  String get progress => phase;
  SanitasProtocol(this.profile, {DateTime Function()? clock})
    : now = clock ?? DateTime.now;
  List<ScaleEvent> start() => [
    SendFrame([0xe6, 1]),
  ];
  SendFrame command(int cmd, [List<int> payload = const []]) =>
      SendFrame([0xe7, cmd, ...payload]);
  SendFrame ack(List<int> b) => command(0xf1, b.sublist(1, 4));
  List<ScaleEvent> discardPartial() {
    _clearLive();
    return [
      ScaleTransfer(0, const {}),
      ScaleMessage(
        'Messung unvollständig. Bitte erneut auf die Waage steigen.',
      ),
    ];
  }

  List<ScaleEvent> receive(List<int> b, {DateTime? receivedAt}) {
    if (phase == 'error' || b.isEmpty) return [];
    if (b[0] == 0xe6 && phase == 'init') {
      if (b.length < 3) return [];
      if (b[1] != 0 || b[2] != 0x20) {
        phase = 'error';
        return [
          ScaleMessage('Die Waage hat die Anmeldung abgelehnt.', error: true),
        ];
      }
      phase = 'ready';
      return [ScaleReady()];
    }
    if (b.length < 2 || b[0] != 0xe7 || phase != 'ready') return [];
    switch (b[1]) {
      case 0x58:
        if (b.length != 5) return [];
        final kg = u16(b, 3) * .05;
        return [ack(b), if (kg > 0 && kg <= 180) ScaleLiveWeight(kg)];
      case 0x59:
        if (b.length < 4 || phase != 'ready') return [];
        if (b[2] != 3 || b[3] < 1 || b[3] > 3) {
          return discardPartial();
        }
        final out = <ScaleEvent>[ack(b)];
        final time = receivedAt ?? now();
        if (_liveStarted != null &&
            time.difference(_liveStarted!) > const Duration(seconds: 15)) {
          _clearLive();
        }
        final key = hexBytes(b);
        if (_liveFrames[b[3]] == key) return out;
        if (b[3] == 1 && b.length == 13 && b[4] == 1) {
          _clearLive();
          _liveStarted = time;
          _liveFrames[1] = key;
          out.add(ScaleTransfer(1, const {}));
        } else if (b[3] == 2 && b.length == 15 && _liveFrames.length == 1) {
          _livePart = b.sublist(4);
          _liveFrames[2] = key;
          out.add(ScaleTransfer(2, decodeBodyValues(_livePart!)));
        } else if (b[3] == 3 &&
            b.length == 15 &&
            _livePart != null &&
            _liveFrames.length == 2) {
          // Every complete measurement belongs to the active app profile,
          // regardless of which scale user the scale reports.
          out.addAll(_decode([..._livePart!, ...b.sublist(4)]));
          _clearLive();
          // ACK a repeated final packet, but never combine it with old data.
          _liveFrames[3] = key;
        } else {
          out.addAll(discardPartial());
        }
        return out;
      default:
        return [];
    }
  }

  void _clearLive() {
    _livePart = null;
    _liveStarted = null;
    _liveFrames.clear();
  }

  List<ScaleEvent> _decode(List<int> bytes) {
    try {
      final m = decodeMeasurement(bytes, profile, now: now(), live: true);
      return [ScaleTransfer(3, m.values), if (_seen.add(m.id)) ScaleReading(m)];
    } on FormatException catch (e) {
      return [ScaleTransfer(0, const {}), ScaleMessage(e.message)];
    }
  }
}

/// Decode only fields whose two bytes have arrived. Water straddles packets.
Map<Metric, double> decodeBodyValues(List<int> b) {
  final values = <Metric, double>{};
  final fields = <Metric, (int, double)>{
    Metric.weight: (4, 20),
    Metric.impedance: (6, 1),
    Metric.fat: (8, 10),
    Metric.water: (10, 10),
    Metric.muscle: (12, 10),
    Metric.bone: (14, 20),
    Metric.bmr: (16, 1),
    Metric.amr: (18, 1),
    Metric.bmi: (20, 10),
  };
  for (final entry in fields.entries) {
    final (offset, divisor) = entry.value;
    if (b.length < offset + 2) continue;
    final value = u16(b, offset) / divisor;
    if (value > 0 && value <= entry.key.max) values[entry.key] = value;
  }
  return values;
}

Measurement decodeMeasurement(
  List<int> b,
  Profile p, {
  required DateTime now,
  bool live = false,
}) {
  if (b.length != 22) {
    throw const FormatException('Unvollständige Messung verworfen.');
  }
  final rawSeconds = ByteData.sublistView(Uint8List.fromList(b)).getUint32(0);
  // Known firmware flag on live measurements (openScale issue #1500).
  final seconds = now.year < 2038 ? rawSeconds & 0x7fffffff : rawSeconds;
  final time = live ? now : DateTime.fromMillisecondsSinceEpoch(seconds * 1000);
  if (time.year < 2000 || time.isAfter(now.add(const Duration(minutes: 5)))) {
    throw const FormatException(
      'Die Uhrzeit der Waage ist ungültig. Bitte erneut verbinden und neu wiegen.',
    );
  }
  final values = decodeBodyValues(b);
  if (!values.containsKey(Metric.weight)) {
    throw const FormatException('Ungültiges Gewicht verworfen.');
  }
  return Measurement(
    // Received live packets belong to the active local profile.
    id: live
        ? 'live:${p.deviceId ?? 'unknown'}:${hexBytes(b)}'
        : 'scale:$seconds',
    profileId: p.id,
    time: time,
    values: values,
    source: 'scale',
    raw: hexBytes(b),
  );
}
