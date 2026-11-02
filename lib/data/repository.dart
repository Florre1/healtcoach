import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../domain/models.dart';

class Repository {
  final Database db;
  Repository(this.db);
  static Future<Repository> open({
    DatabaseFactory? factory,
    String? path,
  }) async {
    final f = factory ?? databaseFactory;
    final database = await f.openDatabase(
      path ?? '${await f.getDatabasesPath()}/healthcoach.db',
      options: OpenDatabaseOptions(
        version: 1,
        singleInstance: path != inMemoryDatabasePath,
        onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
        onCreate: (db, version) async {
          await db.execute(
            'CREATE TABLE profiles (id TEXT PRIMARY KEY, data TEXT NOT NULL)',
          );
          await db.execute(
            'CREATE TABLE measurements (id TEXT PRIMARY KEY, profile_id TEXT NOT NULL REFERENCES profiles(id), timestamp INTEGER NOT NULL, data TEXT NOT NULL)',
          );
          await db.execute(
            'CREATE INDEX measurements_profile_time ON measurements(profile_id, timestamp)',
          );
          await db.execute(
            'CREATE TABLE settings (key TEXT PRIMARY KEY, value TEXT NOT NULL)',
          );
          await db.execute(
            'CREATE TABLE deleted_measurements (id TEXT PRIMARY KEY)',
          );
        },
      ),
    );
    return Repository(database);
  }

  Future<List<Profile>> profiles() async => (await db.query(
    'profiles',
    orderBy: 'rowid',
  )).map((r) => Profile.fromJson(jsonDecode(r['data'] as String))).toList();
  Future<void> saveProfile(Profile p) async {
    await db.transaction((tx) async {
      final data = {'data': jsonEncode(p.toJson())};
      if (await tx.update(
            'profiles',
            data,
            where: 'id = ?',
            whereArgs: [p.id],
          ) ==
          0) {
        await tx.insert('profiles', {'id': p.id, ...data});
      }
    });
  }

  Future<List<Measurement>> measurements(String profileId) async =>
      (await db.query(
            'measurements',
            where: 'profile_id = ?',
            whereArgs: [profileId],
            orderBy: 'timestamp DESC',
          ))
          .map((r) => Measurement.fromJson(jsonDecode(r['data'] as String)))
          .toList();
  Future<bool> saveMeasurement(Measurement m) async {
    return db.transaction((tx) async {
      if (await _alreadyProcessed(tx, m)) return false;
      await tx.rawInsert(
        'INSERT OR IGNORE INTO measurements(id,profile_id,timestamp,data) VALUES(?,?,?,?)',
        [
          m.id,
          m.profileId,
          m.time.millisecondsSinceEpoch,
          jsonEncode(m.toJson()),
        ],
      );
      return Sqflite.firstIntValue(await tx.rawQuery('SELECT changes()')) == 1;
    });
  }

  // Before 1.2, scale IDs included the app profile. Keep those records and
  // deletion markers valid when the shared slot replays the same timestamp.
  Future<bool> _alreadyProcessed(Transaction tx, Measurement m) async {
    final seconds = m.time.millisecondsSinceEpoch ~/ 1000;
    final scaleId =
        m.source == 'scale' &&
        (m.id == 'scale:$seconds' || m.id == 'scale:${m.profileId}:$seconds');
    final where = scaleId ? 'id = ? OR id = ? OR id GLOB ?' : 'id = ?';
    final args = scaleId
        ? [m.id, 'scale:$seconds', 'scale:*:$seconds']
        : [m.id];
    for (final table in ['deleted_measurements', 'measurements']) {
      if ((await tx.query(
        table,
        columns: ['id'],
        where: where,
        whereArgs: args,
        limit: 1,
      )).isNotEmpty) {
        return true;
      }
    }
    return false;
  }

  Future<void> deleteMeasurement(String id) async {
    await db.transaction((tx) async {
      await tx.insert('deleted_measurements', {
        'id': id,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
      await tx.delete('measurements', where: 'id = ?', whereArgs: [id]);
    });
  }

  Future<String?> setting(String key) async {
    final rows = await db.query('settings', where: 'key = ?', whereArgs: [key]);
    return rows.isEmpty ? null : rows.first['value'] as String;
  }

  Future<void> setSetting(String key, String value) async {
    await db.insert('settings', {
      'key': key,
      'value': value,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<String> backup() async => const JsonEncoder.withIndent('  ').convert({
    'format': 'healthcoach',
    'version': 1,
    'createdAt': DateTime.now().toUtc().toIso8601String(),
    'profiles': (await profiles()).map((p) => p.toJson()).toList(),
    'measurements': (await db.query('measurements'))
        .map((r) => jsonDecode(r['data'] as String))
        .toList(),
  });

  /// Validate everything before writing, then merge atomically. Existing entries win.
  Future<int> restore(String contents) async {
    if (contents.length > 20 * 1024 * 1024) {
      throw const FormatException('Sicherung ist zu groß (maximal 20 MB).');
    }
    final j = jsonDecode(contents) as Map<String, dynamic>;
    if (j['format'] != 'healthcoach' || j['version'] != 1) {
      throw const FormatException('Keine unterstützte HealthCoach-Sicherung.');
    }
    final ps = (j['profiles'] as List)
        .map((p) => Profile.fromJson(Map<String, dynamic>.from(p)))
        .toList();
    final ms = (j['measurements'] as List)
        .map((m) => Measurement.fromJson(Map<String, dynamic>.from(m)))
        .toList();
    final ids = ps.map((p) => p.id).toSet();
    if (ids.length != ps.length || ms.any((m) => !ids.contains(m.profileId))) {
      throw const FormatException('Ungültige Profilzuordnung.');
    }
    var count = 0;
    await db.transaction((tx) async {
      for (final p in ps) {
        // Bindings are device-specific. Imported profiles must explicitly reconnect.
        await tx.insert('profiles', {
          'id': p.id,
          'data': jsonEncode(p.withDevice(null, null).toJson()),
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
      }
      for (final m in ms) {
        if (await _alreadyProcessed(tx, m)) continue;
        await tx.insert('measurements', {
          'id': m.id,
          'profile_id': m.profileId,
          'timestamp': m.time.millisecondsSinceEpoch,
          'data': jsonEncode(m.toJson()),
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
        count +=
            Sqflite.firstIntValue(await tx.rawQuery('SELECT changes()')) ?? 0;
      }
    });
    return count;
  }
}
