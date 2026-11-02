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
