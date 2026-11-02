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
