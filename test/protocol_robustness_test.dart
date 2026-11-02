import 'package:flutter_test/flutter_test.dart';
import 'package:healthcoach/bluetooth/sanitas_protocol.dart';

import 'fixtures.dart';

void main() {
  late SanitasProtocol p;
  setUp(() => p = SanitasProtocol(testProfile(), clock: () => testTime));
  final header = [0xe7, 0x59, 3, 1, 1, ...idBytes('0000000000000099')];
  final first = [0xe7, 0x59, 3, 2, ...measurementPacket().take(11)];
  final last = [0xe7, 0x59, 3, 3, ...measurementPacket().skip(11)];
  void ready() => handshake(p);
  List<List<int>> sent(List<ScaleEvent> events) =>
      events.whereType<SendFrame>().map((f) => f.bytes).toList();
  test(
    'empty scale: slot is created with profile data, then measurement starts',
    () {
      expect((p.start().single as SendFrame).bytes, [0xe6, 1]);
      final login = sent(p.receive(sessionReplies[0]));
      expect(login.map((b) => b[0] == 0xe9 ? 0xe9 : b[1]), [0xe9, 0x4f]);
      expect(sent(p.receive(sessionReplies[1])), [
        [0xe7, 0x33],
      ]);
      final create = sent(p.receive(sessionReplies[2])).single;
      expect(create.take(2), [0xe7, 0x31]);
      expect(create.sublist(2, 10), idBytes(appSlotId));
      // TST, 1995-06-15, 180 cm, male + activity 2
      expect(create.sublist(10), [0x54, 0x53, 0x54, 95, 5, 15, 180, 0x82]);
      expect(sent(p.receive(sessionReplies[3])), [
        [0xe7, 0x40, ...idBytes(appSlotId)],
      ]);
      final ready = p.receive(sessionReplies[4]);
      expect(ready.whereType<ScaleReady>().single.bodyData, isTrue);
      expect(p.phase, 'ready');
    },
  );
  test(
    'existing slot is updated, other users are untouched, history never read',
    () {
      p.start();
      p.receive(sessionReplies[0]);
      p.receive(sessionReplies[1]);
      final out = <ScaleEvent>[];
      out.addAll(p.receive([0xe7, 0xf0, 0x33, 0, 2, 8]));
      out.addAll(p.receive(userFrame(2, 1, '0000000000000099', 'TST')));
      out.addAll(p.receive(userFrame(2, 2, appSlotId, 'HC')));
      final frames = sent(out);
      expect(frames.where((b) => b[1] == 0xf1), hasLength(2));
      final update = frames.singleWhere((b) => b[1] != 0xf1);
      expect(update.take(2), [0xe7, 0x35]);
      expect(update.sublist(2, 10), idBytes(appSlotId));
      // TST is taken by another scale user, so the slot shows HC.
      expect(update.sublist(10, 13), [0x48, 0x43, 0]);
      out
        ..clear()
        ..addAll(p.receive([0xe7, 0xf0, 0x35, 0]))
        ..addAll(p.receive([0xe7, 0xf0, 0x40, 0]));
      for (final b in sent(out)) {
        expect([0x30, 0x32, 0x36, 0x41, 0x43], isNot(contains(b[1])));
      }
      expect(out.whereType<ScaleReady>().single.bodyData, isTrue);
    },
  );
  test('full scale falls back to weight-only reception', () {
    p.start();
    p.receive(sessionReplies[0]);
    p.receive(sessionReplies[1]);
    p.receive([0xe7, 0xf0, 0x33, 0, 1, 1]);
    final out = p.receive(userFrame(1, 1, '0000000000000099', 'ABC'));
    expect(sent(out).where((b) => b[1] != 0xf1), isEmpty);
    final ready = out.whereType<ScaleReady>().single;
    expect(ready.bodyData, isFalse);
    expect(ready.note, contains('belegt'));
    expect(p.phase, 'ready');
    p.receive(header);
    p.receive(first);
    expect(p.receive(last).whereType<ScaleReading>(), hasLength(1));
  });
  test('rejected slot or measurement start falls back to weight-only', () {
    for (final reject in [
      [0xe7, 0xf0, 0x31, 1],
      [0xe7, 0xf0, 0x40, 1],
    ]) {
      p = SanitasProtocol(testProfile(), clock: () => testTime);
      p.start();
      for (final reply in sessionReplies.take(reject[2] == 0x31 ? 3 : 4)) {
        p.receive(reply);
      }
      final ready = p.receive(reject).whereType<ScaleReady>().single;
      expect(ready.bodyData, isFalse);
      expect(p.phase, 'ready');
    }
  });
  test('live packets during setup are ignored until measurement start', () {
    p.start();
    p.receive(sessionReplies[0]);
    expect(p.receive([0xe7, 0x58, 1, 6, 64]), isEmpty);
    expect(p.receive(header), isEmpty);
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
    for (final command in [0x42, 0x47, 0x4c]) {
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
