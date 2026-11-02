import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:healthcoach/data/repository.dart';
import 'package:healthcoach/bluetooth/sanitas_protocol.dart';

import 'fixtures.dart';

void main() {
  late Repository repo;
  setUpAll(sqfliteFfiInit);
  setUp(() async {
    repo = await Repository.open(
      factory: databaseFactoryFfi,
      path: inMemoryDatabasePath,
    );
    await repo.saveProfile(testProfile());
  });
  tearDown(() => repo.db.close());
  for (final deleted in [false, true]) {
    test('legacy scale IDs remain deduplicated (deleted: $deleted)', () async {
      final current = decodeMeasurement(
        measurementPacket(),
        testProfile(),
        now: testTime,
      );
      final legacy = Map<String, dynamic>.from(current.toJson());
      legacy['id'] =
          'scale:${current.profileId}:${current.time.millisecondsSinceEpoch ~/ 1000}';
      await repo.db.insert('measurements', {
        'id': legacy['id'],
        'profile_id': current.profileId,
        'timestamp': current.time.millisecondsSinceEpoch,
        'data': jsonEncode(legacy),
      });
      if (deleted) await repo.deleteMeasurement(legacy['id'] as String);
      expect(await repo.saveMeasurement(current), isFalse);
      final backup = jsonDecode(await repo.backup()) as Map<String, dynamic>;
      backup['measurements'] = [current.toJson()];
      expect(await repo.restore(jsonEncode(backup)), 0);
      expect(
        await repo.measurements(current.profileId),
        hasLength(deleted ? 0 : 1),
      );
    });
  }
  test(
    'shared slot history stays on the first receiving app profile',
    () async {
      await repo.saveProfile(testProfile(id: 'profile-2'));
      final first = decodeMeasurement(
        measurementPacket(),
        testProfile(),
        now: testTime,
      );
      final second = decodeMeasurement(
        measurementPacket(),
        testProfile(id: 'profile-2'),
        now: testTime,
      );
      expect(await repo.saveMeasurement(first), isTrue);
      expect(await repo.saveMeasurement(second), isFalse);
      expect(await repo.measurements('profile-2'), isEmpty);
      await repo.deleteMeasurement(first.id);
      expect(await repo.saveMeasurement(second), isFalse);
    },
  );
  test(
    'concurrent repeated sync is idempotent and profile edits preserve data',
    () async {
      final m = decodeMeasurement(
        measurementPacket(),
        testProfile(),
        now: testTime,
      );
      final results = await Future.wait(
        List.generate(5, (_) => repo.saveMeasurement(m)),
      );
      expect(results.where((x) => x), hasLength(1));
      await repo.saveProfile(testProfile().withDevice('AA:BB', 'Sanitas'));
      expect(await repo.measurements('profile-1'), hasLength(1));
    },
  );
  test('profiles isolate measurements; deleted scale data does not reappear on sync', () async {
    await repo.saveProfile(testProfile(id: 'profile-2'));
    final m = decodeMeasurement(
      measurementPacket(),
      testProfile(),
      now: testTime,
    );
    await repo.saveMeasurement(m);
    expect(await repo.measurements('profile-2'), isEmpty);
    await repo.deleteMeasurement(m.id);
    expect(await repo.saveMeasurement(m), isFalse);
    expect(await repo.measurements('profile-1'), isEmpty);
  });
  test(
    'backup restore round trip and repeated restore preserve one copy',
    () async {
      final m = decodeMeasurement(
        measurementPacket(),
        testProfile(),
        now: testTime,
      );
      await repo.saveMeasurement(m);
      final backup = await repo.backup();
      final other = await Repository.open(
        factory: databaseFactoryFfi,
        path: inMemoryDatabasePath,
      );
      try {
        expect(await other.restore(backup), 1);
        expect(await other.restore(backup), 0);
        expect(
          (await other.measurements('profile-1')).single.toJson(),
          m.toJson(),
        );
        expect((await other.profiles()).single.deviceId, isNull);
      } finally {
        await other.db.close();
      }
    },
  );
  test('invalid backup is rejected before importing any profile', () async {
    final bad = jsonDecode(await repo.backup()) as Map<String, dynamic>;
    bad['profiles'] = [testProfile(id: 'new').toJson()];
    bad['measurements'] = [
      decodeMeasurement(
        measurementPacket(),
        testProfile(),
        now: testTime,
      ).toJson(),
    ];
    await expectLater(repo.restore(jsonEncode(bad)), throwsFormatException);
    expect((await repo.profiles()).map((p) => p.id), ['profile-1']);
  });
}
