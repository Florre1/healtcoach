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

class ScaleBound extends ScaleEvent {
  final String remoteId;
  ScaleBound(this.remoteId);
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

class RemoteUser {
  final String id, initials;
  final int year;
  RemoteUser(this.id, this.initials, this.year);
}

String hexBytes(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
List<int> idBytes(String id) => List.generate(
  8,
  (i) => int.parse(id.substring(i * 2, i * 2 + 2), radix: 16),
);

/// Fixed user slot that HealthCoach owns on the scale. All app profiles share
/// it: before each session the active profile's body data is written into it,
/// and every measurement is stored on the profile that is active in the app.
/// Other users on the scale (e.g. from the Sanitas app) are never compared,
/// changed or deleted.
const appSlotId = '4843000000000001';

int u16(List<int> b, int offset) => (b[offset] << 8) | b[offset + 1];
List<int> timeBytes(DateTime date) => (ByteData(
  4,
)..setUint32(0, date.millisecondsSinceEpoch ~/ 1000)).buffer.asUint8List();

class SanitasProtocol {
  final Profile profile;
  final DateTime Function() now;
  final users = <RemoteUser>[];
  String? remote;
  String phase = 'init';
  int capacity = 8;
  List<int>? _savedPart, _livePart;
  int? _savedCount, _userCount;
  DateTime? _liveStarted;
  String _slotInitials = '';
  final _savedFrames = <int, String>{};
  final _userFrames = <int, String>{};
  final _liveFrames = <int, String>{};
  final _seen = <String>{};
  bool get hasPartialLive => _liveStarted != null;
  String get progress =>
      '$phase:$_userCount:${users.length}:$_savedCount:${_savedFrames.length}';
  SanitasProtocol(this.profile, {DateTime Function()? clock})
    : now = clock ?? DateTime.now;
  List<ScaleEvent> start() => [
    SendFrame([0xe6, 0x01]),
  ];
  SendFrame command(int command, [List<int> payload = const []]) =>
      SendFrame([0xe7, command, ...payload]);
  SendFrame ack(List<int> b) => command(0xf1, b.sublist(1, 4));
  List<int> get _uid => idBytes(remote!);
  List<int> get _details => [
    ...List.generate(
      3,
      (i) => i < _slotInitials.length ? _slotInitials.codeUnitAt(i) : 0,
    ),
    profile.birthday.year - 1900,
    profile.birthday.month - 1,
    profile.birthday.day,
    profile.heightCm,
    (profile.sex == 'male' ? 0x80 : 0) | profile.activity,
  ];

  List<ScaleEvent> _fail(String message, {bool retryable = false}) {
    phase = 'error';
    return [ScaleMessage(message, error: true, retryable: retryable)];
  }

  List<ScaleEvent> _history() {
    phase = 'history';
    return [command(0x41, _uid)];
  }

  List<ScaleEvent> _ready() {
    phase = 'starting';
    return [ScaleBound(remote!), command(0x40, _uid)];
  }

  /// Initials must be unique on the scale. Prefer the profile's own, fall back
  /// to HC/HC1… when another scale user already shows the same letters.
  String? _freeInitials() {
    final taken = users
        .where((u) => u.id != appSlotId)
        .map((u) => u.initials.toUpperCase())
        .toSet();
    for (final candidate in [
      profile.initials,
      'HC',
      for (var i = 1; i <= 9; i++) 'HC$i',
    ]) {
      if (!taken.contains(candidate)) return candidate;
    }
    return null;
  }

  /// No matching against scale profiles: use the app slot, write the active
  /// profile's data into it (or create it once) and continue.
  List<ScaleEvent> _selectUser() {
    final initials = _freeInitials();
    if (initials == null) {
      return _fail('Kein freies Kürzel auf der Waage verfügbar.');
    }
    _slotInitials = initials;
    remote = appSlotId;
    if (users.any((u) => u.id == appSlotId)) {
      phase = 'update';
      return [
        command(0x35, [..._uid, ..._details]),
      ];
    }
    if (users.length >= capacity) {
      return _fail(
        'Alle Benutzerplätze der Waage sind belegt. Lösche in der Sanitas-App einen nicht benötigten Benutzer und verbinde erneut.',
      );
    }
    phase = 'create';
    return [
      ScaleMessage('Die Waage wird für HealthCoach eingerichtet.'),
      command(0x31, [..._uid, ..._details]),
    ];
  }

  List<ScaleEvent> receive(List<int> b, {DateTime? receivedAt}) {
    if (phase == 'error' || b.isEmpty) return [];
    if (b[0] == 0xe6 && phase == 'init') {
      if (b.length < 3) return [];
      if (b[1] != 0 || b[2] != 0x20) {
        return _fail('Die Waage hat die Anmeldung abgelehnt.');
      }
      phase = 'status';
      return [
        SendFrame([0xe9, ...timeBytes(now())]),
        command(0x4f, List.filled(8, 0)),
      ];
    }
    if (b.length < 2 || b[0] != 0xe7) return [];
    switch (b[1]) {
      case 0xf0:
        if (b.length < 4) return [];
        return _response(b);
      case 0x34:
        if (b.length != 16) return [];
        final count = b[2], index = b[3];
        final key = hexBytes(b);
        if (_userFrames[index] == key) return [ack(b)];
        if (phase != 'users') return [];
        if (index < 1 ||
            index > count ||
            count > capacity ||
            (_userCount != null && count != _userCount) ||
            index != users.length + 1) {
          return _fail(
            'Benutzerliste unvollständig oder widersprüchlich. Bitte erneut verbinden.',
            retryable: true,
          );
        }
        _userCount = count;
        _userFrames[index] = key;
        final result = <ScaleEvent>[ack(b)];
        users.add(
          RemoteUser(
            hexBytes(b.sublist(4, 12)),
            String.fromCharCodes(b.sublist(12, 15).takeWhile((x) => x != 0)),
            1900 + b[15],
          ),
        );
        if (users.length == count) result.addAll(_selectUser());
        return result;
      case 0x58:
        if (b.length != 5 || phase != 'ready') return [];
        final kg = u16(b, 3) * .05;
        return [ack(b), if (kg > 0 && kg <= 180) ScaleLiveWeight(kg)];
      case 0x42:
        if (b.length != 15 || remote == null) return [];
        // The scale may retransmit a notification when its ACK was lost.
        // ACK it again without consuming a second part or storing twice.
        final frameKey = hexBytes(b);
        if (_savedFrames[b[3]] == frameKey) return [ack(b)];
        if (phase != 'history') return [];
        final index = b[3], count = b[2];
        if (count == 0 ||
            count.isOdd ||
            index < 1 ||
            index > count ||
            index != _savedFrames.length + 1 ||
            (_savedCount != null && count != _savedCount)) {
          return _fail(
            'Messdaten unvollständig oder widersprüchlich. Bitte neu verbinden.',
            retryable: true,
          );
        }
        final out = <ScaleEvent>[ack(b)];
        _savedFrames[index] = frameKey;
        _savedCount = count;
        if (index.isOdd) {
          _savedPart = b.sublist(4);
        } else {
          if (_savedPart == null) {
            return _fail(
              'Messdaten unvollständig. Die Waage behält ihre gespeicherten Werte. Bitte neu verbinden.',
              retryable: true,
            );
          }
          out.addAll(_decode([..._savedPart!, ...b.sublist(4)]));
          _savedPart = null;
        }
        if (index == count && phase != 'error') out.addAll(_ready());
        return out;
      case 0x59:
        if (b.length < 4 || remote == null || phase != 'ready') return [];
        if (b[2] != 3 || b[3] < 1 || b[3] > 3) {
          return _fail(
            'Unbekanntes Messformat. Bitte Diagnoseprotokoll exportieren.',
          );
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
        } else if (b[3] == 2 && b.length == 15 && _liveFrames.length == 1) {
          _livePart = b.sublist(4);
          _liveFrames[2] = key;
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
          _clearLive();
          out.add(
            ScaleMessage(
              'Unvollständige Messung verworfen. Bitte erneut wiegen.',
            ),
          );
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

  List<ScaleEvent> _response(List<int> b) {
    final cmd = b[2];
    if (cmd == 0x4f && phase == 'status' && b.length >= 12) {
      phase = 'users';
      // Reading is in kg regardless of the display unit. Leave scale settings intact.
      return [if (b[4] <= 100) ScaleBattery(b[4]), command(0x33)];
    }
    if (cmd == 0x33 && phase == 'users' && b.length >= 6) {
      if (b[3] != 0) return _fail('Benutzerliste konnte nicht gelesen werden.');
      capacity = b[5];
      if (capacity < 1 ||
          capacity > 8 ||
          b[4] > capacity ||
          (_userCount != null && _userCount != b[4])) {
        return _fail(
          'Ungültige Benutzeranzahl von der Waage.',
          retryable: true,
        );
      }
      _userCount = b[4];
      if (b[4] == 0) return _selectUser();
    }
    if (cmd == 0x35 && phase == 'update') {
      if (b[3] != 0) {
        return _fail('Waagenprofil konnte nicht aktualisiert werden.');
      }
      return [ScaleBound(remote!), ..._history()];
    }
    if (cmd == 0x31 && phase == 'create') {
      if (b[3] != 0) {
        return _fail(switch (b[3]) {
          1 => 'Die Waage hat keinen freien Benutzerplatz.',
          2 => 'Benutzerkennung belegt. Bitte erneut verbinden.',
          3 => 'Kürzel bereits belegt. Bitte ein anderes wählen.',
          _ => 'Waagenprofil konnte nicht angelegt werden.',
        });
      }
      return _ready();
    }
    if (cmd == 0x41 && phase == 'history') {
      if (b.length < 5 || b[4] != 0) {
        return _fail('Gespeicherte Messungen konnten nicht gelesen werden.');
      }
      if (b[3].isOdd || (_savedCount != null && _savedCount != b[3])) {
        return _fail(
          'Ungültige Anzahl gespeicherter Messdaten.',
          retryable: true,
        );
      }
      _savedCount = b[3];
      if (b[3] == 0) return _ready();
    }
    if (cmd == 0x40 && phase == 'starting') {
      if (b[3] != 0) {
        return _fail(
          'Messung konnte nicht gestartet werden. Waage kurz antippen und erneut verbinden.',
          retryable: true,
        );
      }
      phase = 'ready';
      return [ScaleReady()];
    }
    return [];
  }

  List<ScaleEvent> _decode(List<int> bytes) {
    try {
      final m = decodeMeasurement(bytes, profile, now: now());
      if (m.time.isBefore(profile.trackingSince) || !_seen.add(m.id)) return [];
      return [ScaleReading(m)];
    } on FormatException catch (e) {
      return _fail(e.message, retryable: true);
    }
  }
}

Measurement decodeMeasurement(List<int> b, Profile p, {required DateTime now}) {
  if (b.length != 22) {
    throw const FormatException('Unvollständige Messung verworfen.');
  }
  final rawSeconds = ByteData.sublistView(Uint8List.fromList(b)).getUint32(0);
  // Known firmware flag on live measurements (openScale issue #1500).
  final seconds = now.year < 2038 ? rawSeconds & 0x7fffffff : rawSeconds;
  final time = DateTime.fromMillisecondsSinceEpoch(seconds * 1000);
  if (time.year < 2000 || time.isAfter(now.add(const Duration(minutes: 5)))) {
    throw const FormatException(
      'Die Uhrzeit der Waage ist ungültig. Bitte erneut verbinden und neu wiegen.',
    );
  }
  final values = <Metric, double>{Metric.weight: u16(b, 4) * .05};
  if (values[Metric.weight]! <= 0 || values[Metric.weight]! > 180) {
    throw const FormatException('Ungültiges Gewicht verworfen.');
  }
  final candidates = {
    Metric.impedance: u16(b, 6).toDouble(),
    Metric.fat: u16(b, 8) / 10,
    Metric.water: u16(b, 10) / 10,
    Metric.muscle: u16(b, 12) / 10,
    Metric.bone: u16(b, 14) * .05,
    Metric.bmr: u16(b, 16).toDouble(),
    Metric.amr: u16(b, 18).toDouble(),
    Metric.bmi: u16(b, 20) / 10,
  };
  for (final e in candidates.entries) {
    if (e.value > 0 && e.value <= e.key.max) values[e.key] = e.value;
  }
  return Measurement(
    // Profile-independent: the shared app slot re-sends its history on every
    // connect, so a measurement is stored once, on the first profile receiving it.
    id: 'scale:$seconds',
    profileId: p.id,
    time: time,
    values: values,
    source: 'scale',
    raw: hexBytes(b),
  );
}
