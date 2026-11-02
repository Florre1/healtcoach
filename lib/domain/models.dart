import 'dart:math';

String newId() =>
    '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}${Random.secure().nextInt(0x7fffffff).toRadixString(36)}';

class Profile {
  final String id, name, initials, sex;
  final DateTime birthday, trackingSince;
  final int heightCm, activity;
  final double goalKg;
  final String? deviceId, deviceName, remoteId;

  const Profile({
    required this.id,
    required this.name,
    required this.initials,
    required this.sex,
    required this.birthday,
    required this.heightCm,
    required this.activity,
    required this.goalKg,
    required this.trackingSince,
    this.deviceId,
    this.deviceName,
    this.remoteId,
  });

  Profile withDevice(String? id, String? name, {String? remote}) => Profile(
    id: this.id,
    name: this.name,
    initials: initials,
    sex: sex,
    birthday: birthday,
    heightCm: heightCm,
    activity: activity,
    goalKg: goalKg,
    trackingSince: trackingSince,
    deviceId: id,
    deviceName: name,
    remoteId: remote,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'initials': initials,
    'sex': sex,
    'birthday': birthday.toIso8601String(),
    'heightCm': heightCm,
    'activity': activity,
    'goalKg': goalKg,
    'trackingSince': trackingSince.toIso8601String(),
    'deviceId': deviceId,
    'deviceName': deviceName,
    'remoteId': remoteId,
  };

  factory Profile.fromJson(Map<String, dynamic> j) {
    final p = Profile(
      id: j['id'] as String,
      name: j['name'] as String,
      initials: j['initials'] as String,
      sex: j['sex'] as String,
      birthday: DateTime.parse(j['birthday'] as String),
      heightCm: j['heightCm'] as int,
      activity: j['activity'] as int,
      goalKg: (j['goalKg'] as num).toDouble(),
      trackingSince: DateTime.parse(j['trackingSince'] as String),
      deviceId: j['deviceId'] as String?,
      deviceName: j['deviceName'] as String?,
      remoteId: j['remoteId'] as String?,
    );
    if (p.id.isEmpty ||
        p.name.trim().isEmpty ||
        p.name.length > 60 ||
        !RegExp(r'^[A-Z0-9]{1,3}$').hasMatch(p.initials) ||
        !['male', 'female'].contains(p.sex) ||
        p.heightCm < 100 ||
        p.heightCm > 220 ||
        p.activity < 1 ||
        p.activity > 5 ||
        !p.goalKg.isFinite ||
        p.goalKg < 20 ||
        p.goalKg > 180 ||
        p.birthday.year < 1900 ||
        p.birthday.isAfter(DateTime.now()) ||
        (p.remoteId != null &&
            !RegExp(r'^[0-9a-f]{16}$').hasMatch(p.remoteId!))) {
      throw const FormatException('Ungültiges Profil in der Sicherung.');
    }
    return p;
  }
}

enum Metric {
  weight('Gewicht', 'kg', 'Dein Körpergewicht.', 2, 180),
  bmi(
    'BMI',
    '',
    'Body-Mass-Index. Bei manuellen Einträgen aus Gewicht und gespeicherter Körpergröße berechnet.',
    1,
    180,
  ),
  fat('Körperfett', '%', 'Von der Waage geschätzter Körperfettanteil.', 1, 100),
  water('Körperwasser', '%', 'Von der Waage geschätzter Wasseranteil.', 1, 100),
  muscle('Muskeln', '%', 'Von der Waage geschätzter Muskelanteil.', 1, 100),
  bone('Knochenmasse', 'kg', 'Von der Waage geschätzte Knochenmasse.', 2, 20),
  bmr(
    'Grundumsatz',
    'kcal',
    'BMR: geschätzter täglicher Energiebedarf in Ruhe, von der Waage übermittelt.',
    0,
    10000,
  ),
  amr(
    'Aktivitätsumsatz',
    'kcal',
    'AMR: geschätzter täglicher Energiebedarf einschließlich Aktivität, von der Waage übermittelt.',
    0,
    20000,
  ),
  impedance(
    'Impedanz',
    'Ω',
    'Elektrischer Widerstand aus der Körperanalyse. Technischer Messwert der Waage.',
    0,
    10000,
  );

  final String label, unit, explanation;
  final int digits;
  final double max;
  const Metric(this.label, this.unit, this.explanation, this.digits, this.max);
}

class Measurement {
  final String id, profileId, source;
  final DateTime time;
  final Map<Metric, double> values;
  final String note;
  final String? raw;
  const Measurement({
    required this.id,
    required this.profileId,
    required this.time,
    required this.values,
    required this.source,
    this.note = '',
    this.raw,
  });
  double get weight => values[Metric.weight]!;
  Map<String, dynamic> toJson() => {
    'id': id,
    'profileId': profileId,
    'time': time.toUtc().toIso8601String(),
    'source': source,
    'note': note,
    'raw': raw,
    'values': values.map((k, v) => MapEntry(k.name, v)),
  };
  factory Measurement.fromJson(Map<String, dynamic> j) {
    final data = (j['values'] as Map).cast<String, dynamic>();
    final values = <Metric, double>{};
    for (final m in Metric.values) {
      if (!data.containsKey(m.name)) continue;
      final value = (data[m.name] as num).toDouble();
      if (!value.isFinite || value <= 0 || value > m.max) {
        throw FormatException('Ungültiger Wert: ${m.label}');
      }
      values[m] = value;
    }
    final time = DateTime.parse(j['time'] as String).toLocal();
    if (!values.containsKey(Metric.weight) ||
        !['scale', 'manual'].contains(j['source']) ||
        time.year < 2000 ||
        time.isAfter(DateTime.now().add(const Duration(days: 1)))) {
      throw const FormatException('Ungültige Messung in der Sicherung.');
    }
    return Measurement(
      id: j['id'] as String,
      profileId: j['profileId'] as String,
      time: time,
      values: values,
      source: j['source'] as String,
      note: j['note'] as String? ?? '',
      raw: j['raw'] as String?,
    );
  }
}

/// Last measurement of each local calendar day; no invented values on missing days.
List<Measurement> dailyMeasurements(
  List<Measurement> measurements,
  Metric metric,
) {
  final days = <String, Measurement>{};
  final sorted = [...measurements]..sort((a, b) => a.time.compareTo(b.time));
  for (final m in sorted) {
    if (!m.values.containsKey(metric)) continue;
    final t = m.time.toLocal();
    days['${t.year}-${t.month}-${t.day}'] = m;
  }
  return days.values.toList();
}
