import 'package:flutter_test/flutter_test.dart';
import 'package:healthcoach/bluetooth/sanitas_protocol.dart';

import 'fixtures.dart';

void main() {
  late SanitasProtocol p;
  setUp(() => p = SanitasProtocol(testProfile(), clock: () => testTime));
  final header = [0xe7, 0x59, 3, 1, 1, ...idBytes('0000000000000099')];
  final first = [0xe7, 0x59, 3, 2, ...measurementPacket().take(11)];
  final last = [0xe7, 0x59, 3, 3, ...measurementPacket().skip(11)];
  void ready() => p.receive([0xe6, 0, 0x20]);
  test('handshake enters receive mode without profile or history commands', () {
    expect((p.start().single as SendFrame).bytes, [0xe6, 1]);
    final events = p.receive([0xe6, 0, 0x20]);
    expect(events.whereType<ScaleReady>(), hasLength(1));
    expect(events.whereType<SendFrame>(), isEmpty);
    for (final command in [0x31, 0x33, 0x35, 0x36, 0x40, 0x41]) {
      expect(p.receive([0xe7, 0xf0, command, 0, 0, 8]), isEmpty);
    }
  });
  test(
    'foreign owner is ignored; complete reading belongs to active app profile',
    () {
      ready();
      p.receive(header);
      p.receive(first);
      final out = p.receive(last);
      final m = out.whereType<ScaleReading>().single.measurement;
      expect(m.profileId, testProfile().id);
      expect(m.weight, 80);
      expect(m.time, testTime);
      expect(out.whereType<SendFrame>().single.bytes, [0xe7, 0xf1, 0x59, 3, 3]);
    },
  );
  test('history and unsolicited user lists are ignored', () {
    ready();
    for (final command in [0x34, 0x42, 0x47, 0x4c]) {
      expect(
        p.receive([0xe7, command, 2, 1, ...measurementPacket().take(11)]),
        isEmpty,
      );
    }
  });
  test('live notifications before handshake cannot save data', () {
    for (final b in [header, first, last]) {
      expect(p.receive(b), isEmpty);
    }
  });
  test('missing and expired headers cannot splice records; next measurement recovers', () {
    ready();
    p.receive(first);
    expect(p.receive(last).whereType<ScaleReading>(), isEmpty);
    p.receive(header, receivedAt: testTime);
    p.receive(first, receivedAt: testTime);
    expect(
      p
          .receive(last, receivedAt: testTime.add(const Duration(seconds: 16)))
          .whereType<ScaleReading>(),
      isEmpty,
    );
    p.receive(header);
    p.receive(first);
    expect(p.receive(last).whereType<ScaleReading>(), hasLength(1));
  });
  test('retransmissions are acknowledged and saved once', () {
    ready();
    p.receive(header);
    p.receive(first);
    p.receive(header);
    p.receive(first);
    expect(p.receive(last).whereType<ScaleReading>(), hasLength(1));
    expect(p.receive(last).whereType<ScaleReading>(), isEmpty);
    p.receive(header);
    p.receive(first);
    expect(p.receive(last).whereType<ScaleReading>(), isEmpty);
  });
  test('malformed frames cannot poison subsequent live reception', () {
    ready();
    p.receive(header);
    p.receive(first);
    p.receive(header.take(8).toList());
    expect(p.receive(last).whereType<ScaleReading>(), isEmpty);
    p.receive(header);
    p.receive(first);
    expect(p.receive(last).whereType<ScaleReading>(), hasLength(1));
  });
  test('all truncated packet prefixes are safe', () {
    ready();
    for (final frame in [
      header,
      first,
      last,
      [0xe7, 0x58, 0, 6, 64],
    ]) {
      for (var i = 0; i < frame.length; i++) {
        expect(() => p.receive(frame.take(i).toList()), returnsNormally);
      }
    }
  });
  test('invalid weight is discarded without reconnecting', () {
    ready();
    p.receive(header);
    p.receive(
      [...first]
        ..[8] = 0
        ..[9] = 0,
    );
    expect(p.receive(last).whereType<ScaleReading>(), isEmpty);
    expect(p.phase, 'ready');
  });
  test('scale clock is not a prerequisite for live reception', () {
    ready();
    p.receive(header);
    p.receive([
      0xe7,
      0x59,
      3,
      2,
      ...measurementPacket(time: DateTime(1970)).take(11),
    ]);
    expect(
      p.receive(last).whereType<ScaleReading>().single.measurement.time,
      testTime,
    );
  });
}
