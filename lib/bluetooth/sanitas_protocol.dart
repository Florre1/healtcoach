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
  ScaleMessage(this.text, {this.error = false});
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
  int? _savedIndex, _savedCount;
  String? _liveOwner;
  String? _lastSavedFrame;
  final _seen = <String>{};
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
      (i) => i < profile.initials.length ? profile.initials.codeUnitAt(i) : 0,
    ),
    profile.birthday.year - 1900,
    profile.birthday.month - 1,
    profile.birthday.day,
    profile.heightCm,
    (profile.sex == 'male' ? 0x80 : 0) | profile.activity,
  ];

  List<ScaleEvent> _fail(String message) {
    phase = 'error';
    return [ScaleMessage(message, error: true)];
  }

  List<ScaleEvent> _history() {
    phase = 'history';
    return [command(0x41, _uid)];
  }

  List<ScaleEvent> _ready() {
    phase = 'ready';
    return [
      ScaleBound(remote!),
      ScaleReady(),
      ScaleMessage('Bereit. Steige barfuß auf die Waage.'),
      command(0x40, _uid),
    ];
  }

  List<ScaleEvent> _selectUser() {
    final matches = users
        .where(
          (u) => profile.remoteId != null
              ? u.id == profile.remoteId
              : u.initials.toUpperCase() == profile.initials &&
                    u.year == profile.birthday.year,
        )
        .toList();
    if (matches.length > 1) {
      return _fail(
        'Mehrere passende Waagenprofile. Bitte ein eindeutiges Kürzel verwenden.',
      );
    }
    if (matches.isNotEmpty) {
      remote = matches.single.id;
      phase = 'details';
      return [command(0x36, _uid)];
    }
    if (profile.remoteId != null) {
      return _fail(
        'Das gespeicherte Waagenprofil fehlt. Trenne die Zuordnung im Profil und verbinde die Waage neu.',
      );
    }
    if (users.length >= capacity) {
      return _fail(
        'Alle Benutzerplätze der Waage sind belegt. Nutze dein bestehendes Kürzel und Geburtsdatum.',
      );
    }
    if (users.any((u) => u.initials.toUpperCase() == profile.initials)) {
      return _fail(
        'Dieses Kürzel gehört bereits zu einem anderen Waagenprofil. Bitte ein anderes Kürzel wählen.',
      );
    }
    var highest = BigInt.from(100);
    for (final u in users) {
      final id = BigInt.parse(u.id, radix: 16);
      if (id > highest) highest = id;
    }
    final next = highest + BigInt.one;
    if (next.bitLength > 64) {
      return _fail('Keine freie Benutzerkennung verfügbar.');
    }
    remote = next.toRadixString(16).padLeft(16, '0');
    phase = 'create';
    return [
      ScaleMessage('Dein Profil wird auf der Waage eingerichtet.'),
      command(0x31, [..._uid, ..._details]),
    ];
  }

  List<ScaleEvent> receive(List<int> b) {
    if (phase == 'error' || b.isEmpty) return [];
    if (b[0] == 0xe6 && phase == 'init') {
      if (b.length < 3 || b[1] != 0 || b[2] != 0x20) {
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
        if (b.length < 16 || phase != 'users') return [];
        final count = b[2], index = b[3];
        if (index < 1 || index > count || count > 8) {
          return _fail('Ungültige Benutzerliste von der Waage.');
        }
        final result = <ScaleEvent>[ack(b)];
        if (index == users.length + 1) {
          users.add(
            RemoteUser(
              hexBytes(b.sublist(4, 12)),
              String.fromCharCodes(b.sublist(12, 15).takeWhile((x) => x != 0)),
              1900 + b[15],
            ),
          );
        } else if (index > users.length) {
          return _fail('Benutzerliste unvollständig. Bitte erneut verbinden.');
        }
        if (users.length == count) result.addAll(_selectUser());
        return result;
      case 0x58:
        if (b.length < 5) return [];
        final kg = u16(b, 3) * .05;
        return [ack(b), if (kg > 0 && kg <= 180) ScaleLiveWeight(kg)];
      case 0x42:
        if (b.length != 15 || remote == null) return [];
        // The scale may retransmit a notification when its ACK was lost.
        // ACK it again without consuming a second part or storing twice.
        final frameKey = hexBytes(b);
        if (frameKey == _lastSavedFrame) return [ack(b)];
        if (phase != 'history') return [];
        final index = b[3], count = b[2];
        if (count == 0 || count.isOdd || index < 1 || index > count) {
          return _fail('Ungültige Messdatenfolge. Bitte neu verbinden.');
        }
        final out = <ScaleEvent>[ack(b)];
        _lastSavedFrame = frameKey;
        if (index.isOdd) {
          _savedPart = b.sublist(4);
          _savedIndex = index;
          _savedCount = count;
        } else {
          if (_savedPart == null ||
              _savedIndex != index - 1 ||
              _savedCount != count) {
            return _fail(
              'Messdaten unvollständig. Die Waage behält ihre gespeicherten Werte. Bitte neu verbinden.',
            );
          }
          out.addAll(_decode([..._savedPart!, ...b.sublist(4)]));
          _savedPart = null;
        }
        if (index == count) out.addAll(_ready());
        return out;
      case 0x59:
        if (b.length < 4 || remote == null) return [];
        if (b[2] != 3 || b[3] < 1 || b[3] > 3) {
          return _fail(
            'Unbekanntes Messformat. Bitte Diagnoseprotokoll exportieren.',
          );
        }
        final out = <ScaleEvent>[ack(b)];
        if (b[3] == 1 && b.length >= 13) {
          _liveOwner = hexBytes(b.sublist(5, 13));
          _livePart = null;
        } else if (b[3] == 2 && b.length == 15) {
          _livePart = b.sublist(4);
        } else if (b[3] == 3 && b.length == 15 && _livePart != null) {
          if (_liveOwner == remote) {
            out.addAll(_decode([..._livePart!, ...b.sublist(4)]));
          } else {
            out.add(
              ScaleMessage(
                'Messung gehört zu einem anderen Waagenprofil und wurde nicht übernommen.',
              ),
            );
          }
          _livePart = null;
          _liveOwner = null;
        }
        return out;
      default:
        return [];
    }
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
      if (b[4] == 0) return _selectUser();
    }
    if (cmd == 0x36 && phase == 'details') {
      if (b[3] != 0 || b.length < 12) {
        return _fail('Waagenprofil konnte nicht geprüft werden.');
      }
      final samePerson =
          b[7] + 1900 == profile.birthday.year &&
          b[8] + 1 == profile.birthday.month &&
          b[9] == profile.birthday.day &&
          ((b[11] & 0x80) != 0) == (profile.sex == 'male');
      if (!samePerson) {
        return _fail(
          'Geburtsdatum oder Geschlecht stimmen nicht mit dem Waagenprofil überein. Prüfe dein Profil oder nutze ein neues Kürzel.',
        );
      }
      if (b[10] != profile.heightCm || (b[11] & 0x0f) != profile.activity) {
        phase = 'update';
        return [
          command(0x35, [..._uid, ..._details]),
        ];
      }
      return [ScaleBound(remote!), ..._history()];
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
      if (b[3] == 0) return _ready();
    }
    if (cmd == 0x40 && b[3] != 0) {
      return _fail(
        'Messung konnte nicht gestartet werden. Waage kurz antippen und erneut verbinden.',
      );
    }
    return [];
  }

  List<ScaleEvent> _decode(List<int> bytes) {
    try {
      final m = decodeMeasurement(bytes, profile, now: now());
      if (m.time.isBefore(profile.trackingSince) || !_seen.add(m.id)) return [];
      return [ScaleReading(m), ScaleMessage('Messung empfangen.')];
    } on FormatException catch (e) {
      return [ScaleMessage(e.message, error: true)];
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
    id: 'scale:${p.id}:$seconds',
    profileId: p.id,
    time: time,
    values: values,
    source: 'scale',
    raw: hexBytes(b),
  );
}
