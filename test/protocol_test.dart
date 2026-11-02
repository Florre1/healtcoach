import 'package:flutter_test/flutter_test.dart';
import 'package:healthcoach/bluetooth/sanitas_protocol.dart';
import 'package:healthcoach/domain/models.dart';

import 'fixtures.dart';

void main() {
  group('SBF70 decoder', () {
    test('decodes nine transmitted values and keeps original bytes', () {
      final reading = decodeMeasurement(
        measurementPacket(),
        testProfile(),
        now: testTime,
      );
      expect(reading.weight, 80);
      expect(reading.values[Metric.fat], 21.5);
      expect(reading.values[Metric.water], 57.2);
      expect(reading.values[Metric.muscle], 40.1);
      expect(reading.values[Metric.bone], closeTo(3.2, .0001));
      expect(reading.values[Metric.bmi], 24.7);
      expect(reading.values[Metric.bmr], 1780);
      expect(reading.values[Metric.amr], 2670);
      expect(reading.values[Metric.impedance], 510);
      expect(reading.raw?.length, 44);
    });
    test('live timestamp flag and stored timestamp produce same ID', () {
      final live = decodeMeasurement(
        measurementPacket(flag: true),
        testProfile(),
        now: testTime,
      );
      final stored = decodeMeasurement(
        measurementPacket(),
        testProfile(),
        now: testTime,
      );
      expect(live.id, stored.id);
      expect(live.time, testTime);
    });
    test('does not turn absent body values into estimates', () {
      expect(
        decodeMeasurement(
          measurementPacket(body: false),
          testProfile(),
          now: testTime,
        ).values,
        {Metric.weight: 80.0},
      );
    });
    test('rejects truncated, zero weight and future-date payloads', () {
      expect(
        () => decodeMeasurement([0, 1], testProfile(), now: testTime),
        throwsFormatException,
      );
      final zero = measurementPacket()
        ..[4] = 0
        ..[5] = 0;
      expect(
        () => decodeMeasurement(zero, testProfile(), now: testTime),
        throwsFormatException,
      );
      expect(
        () => decodeMeasurement(
          measurementPacket(time: testTime.add(const Duration(days: 1))),
          testProfile(),
          now: testTime,
        ),
        throwsFormatException,
      );
    });
  });
  group('SBF70 session', () {
    late SanitasProtocol protocol;
    setUp(
      () => protocol = SanitasProtocol(testProfile(), clock: () => testTime),
    );
    test(
      'initializes, creates profile with zero-based month and becomes ready',
      () {
        expect((protocol.start().single as SendFrame).bytes, [0xe6, 1]);
        handshake(protocol);
        final add = protocol
            .receive([0xe7, 0xf0, 0x33, 0, 0, 8])
            .whereType<SendFrame>()
            .single
            .bytes;
        expect(add, [
          0xe7,
          0x31,
          ...idBytes('0000000000000065'),
          ...'TST'.codeUnits,
          95,
          5,
          15,
          180,
          0x82,
        ]);
        final ready = protocol.receive([0xe7, 0xf0, 0x31, 0]);
        expect(ready.whereType<ScaleReady>(), hasLength(1));
        expect(
          ready.whereType<ScaleBound>().single.remoteId,
          '0000000000000065',
        );
      },
    );
    test('verifies full birth date before using matching initials/year', () {
      handshake(protocol);
      protocol.receive([0xe7, 0xf0, 0x33, 0, 1, 8]);
      protocol.receive(remoteUserFrame());
      final out = protocol.receive(detailsFrame(day: 16));
      expect(out.whereType<ScaleMessage>().single.error, isTrue);
      expect(out.whereType<SendFrame>(), isEmpty);
    });
    test('refuses to overwrite another person with the same initials', () {
      handshake(protocol);
      protocol.receive([0xe7, 0xf0, 0x33, 0, 1, 8]);
      final out = protocol.receive(remoteUserFrame(year: 1994));
      expect(out.whereType<ScaleMessage>().single.error, isTrue);
      expect(
        out.whereType<SendFrame>().any((e) => e.bytes[1] == 0x31),
        isFalse,
      );
    });
    test('reassembles history and never deletes scale history', () {
      existingUser(protocol);
      protocol.receive([0xe7, 0xf0, 0x41, 2, 0]);
      final payload = measurementPacket();
      final first = protocol.receive([0xe7, 0x42, 2, 1, ...payload.take(11)]);
      expect(first.whereType<ScaleReading>(), isEmpty);
      final second = protocol.receive([0xe7, 0x42, 2, 2, ...payload.skip(11)]);
      expect(second.whereType<ScaleReading>().single.measurement.weight, 80);
      expect(second.whereType<ScaleReady>(), hasLength(1));
      expect(
        second.whereType<SendFrame>().any(
          (e) => [0x43, 0x32, 0x49].contains(e.bytes[1]),
        ),
        isFalse,
      );
    });
    test(
      'ACKs a retransmitted saved frame without duplicate data or errors',
      () {
        existingUser(protocol);
        final data = measurementPacket();
        final first = [0xe7, 0x42, 2, 1, ...data.take(11)];
        final last = [0xe7, 0x42, 2, 2, ...data.skip(11)];
        protocol.receive(first);
        expect(protocol.receive(first).whereType<SendFrame>(), hasLength(1));
        expect(protocol.receive(last).whereType<ScaleReading>(), hasLength(1));
        final repeat = protocol.receive(last);
        expect(repeat.whereType<SendFrame>(), hasLength(1));
        expect(repeat.whereType<ScaleReading>(), isEmpty);
        expect(protocol.phase, 'ready');
      },
    );
    test('does not merge saved chunks that arrive out of sequence', () {
      existingUser(protocol);
      final out = protocol.receive([
        0xe7,
        0x42,
        2,
        2,
        ...measurementPacket().skip(11),
      ]);
      expect(out.whereType<ScaleReading>(), isEmpty);
      expect(out.whereType<ScaleMessage>().single.error, isTrue);
    });
    test('does not assign a different remote user live measurement to active profile', () {
      existingUser(protocol);
      protocol.receive([0xe7, 0xf0, 0x41, 0, 0]);
      final data = measurementPacket();
      protocol.receive([0xe7, 0x59, 3, 1, 1, ...idBytes('0000000000000099')]);
      protocol.receive([0xe7, 0x59, 3, 2, ...data.take(11)]);
      expect(
        protocol.receive([
          0xe7,
          0x59,
          3,
          3,
          ...data.skip(11),
        ]).whereType<ScaleReading>(),
        isEmpty,
      );
    });
    test(
      'live frames save exactly once and raw live weight is not persisted',
      () {
        existingUser(protocol);
        protocol.receive([0xe7, 0xf0, 0x41, 0, 0]);
        expect(
          protocol.receive([0xe7, 0x58, 0, 6, 64]).whereType<ScaleReading>(),
          isEmpty,
        );
        final data = measurementPacket();
        List<ScaleEvent> frame() {
          protocol.receive([
            0xe7,
            0x59,
            3,
            1,
            1,
            ...idBytes('0000000000000065'),
          ]);
          protocol.receive([0xe7, 0x59, 3, 2, ...data.take(11)]);
          return protocol.receive([0xe7, 0x59, 3, 3, ...data.skip(11)]);
        }

        expect(frame().whereType<ScaleReading>(), hasLength(1));
        expect(frame().whereType<ScaleReading>(), isEmpty);
      },
    );
    test('history before profile tracking start is not imported', () {
      existingUser(protocol);
      final data = measurementPacket(time: DateTime(2026, 9, 1));
      protocol.receive([0xe7, 0x42, 2, 1, ...data.take(11)]);
      expect(
        protocol.receive([
          0xe7,
          0x42,
          2,
          2,
          ...data.skip(11),
        ]).whereType<ScaleReading>(),
        isEmpty,
      );
    });
    test('all truncated packet prefixes are safe to parse', () {
      for (final packet in [
        remoteUserFrame(),
        detailsFrame(),
        [0xe7, 0x59, 3, 1, 1, ...idBytes('0000000000000065')],
        [0xe7, 0xf0, 0x4f, 0, 90, 20, 20, 1, 0, 0, 0, 1],
      ]) {
        for (var i = 0; i < packet.length; i++) {
          final p = SanitasProtocol(testProfile(), clock: () => testTime);
          handshake(p);
          expect(() => p.receive(packet.take(i).toList()), returnsNormally);
        }
      }
    });
  });
  test('daily graph uses latest available value per day, sorted, without filling gaps', () {
    Measurement row(String id, DateTime t, Map<Metric, double> v) =>
        Measurement(
          id: id,
          profileId: 'p',
          time: t,
          values: v,
          source: 'manual',
        );
    final rows = [
      row('late', DateTime(2026, 10, 30, 20), {Metric.weight: 81}),
      row('early', DateTime(2026, 10, 30, 8), {
        Metric.weight: 80,
        Metric.fat: 20,
      }),
      row('other', DateTime(2026, 10, 28), {Metric.weight: 82}),
    ];
    expect(dailyMeasurements(rows, Metric.weight).map((m) => m.id), [
      'other',
      'late',
    ]);
    expect(dailyMeasurements(rows, Metric.fat).map((m) => m.id), ['early']);
  });
}
