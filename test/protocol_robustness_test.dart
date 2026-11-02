import 'package:flutter_test/flutter_test.dart';
import 'package:healthcoach/bluetooth/sanitas_protocol.dart';

import 'fixtures.dart';

void main() {
  late SanitasProtocol p;
  setUp(() => p = SanitasProtocol(testProfile(), clock: () => testTime));
  List<int> part(int index, {int count = 2}) => [
    0xe7,
    0x42,
    count,
    index,
    ...(index.isOdd
        ? measurementPacket().take(11)
        : measurementPacket().skip(11)),
  ];
  final liveHeader = [0xe7, 0x59, 3, 1, 1, ...idBytes('0000000000000065')];
  final liveFirst = [0xe7, 0x59, 3, 2, ...measurementPacket().take(11)];
  final liveLast = [0xe7, 0x59, 3, 3, ...measurementPacket().skip(11)];
  void ready() {
    existingUser(p);
    p.receive([0xe7, 0xf0, 0x41, 0, 0]);
    p.receive([0xe7, 0xf0, 0x40, 0]);
  }

  test('truncated handshake waits for a complete reply', () {
    expect(p.receive([0xe6]), isEmpty);
    expect(p.receive([0xe6, 0]), isEmpty);
    expect(p.phase, 'init');
    expect(p.receive([0xe6, 0, 0x20]).whereType<SendFrame>(), hasLength(2));
  });
  test('rejected measurement start never emits ready', () {
    existingUser(p);
    expect(
      p.receive([0xe7, 0xf0, 0x41, 0, 0]).whereType<ScaleReady>(),
      isEmpty,
    );
    final error = p
        .receive([0xe7, 0xf0, 0x40, 1])
        .whereType<ScaleMessage>()
        .single;
    expect(error.error, isTrue);
    expect(error.retryable, isTrue);
    expect(p.phase, 'error');
  });
  test('live data is ignored until the scale confirmed measurement start', () {
    handshake(p);
    p.receive([0xe7, 0xf0, 0x33, 0, 1, 8]);
    p.receive(remoteUserFrame());
    expect(p.phase, 'update');
    expect(
      [
        liveHeader,
        liveFirst,
        liveLast,
      ].expand(p.receive).whereType<ScaleReading>(),
      isEmpty,
    );
  });
  test('skipping a whole historical measurement is rejected', () {
    existingUser(p);
    p.receive([0xe7, 0xf0, 0x41, 4, 0]);
    final result = p.receive(part(3, count: 4));
    expect(result.whereType<ScaleReading>(), isEmpty);
    expect(result.whereType<ScaleMessage>().single.retryable, isTrue);
  });
  test('changed count or payload cannot splice two history records', () {
    for (final second in [part(2, count: 4), part(1)..[5] ^= 1]) {
      p = SanitasProtocol(testProfile(), clock: () => testTime);
      existingUser(p);
      p.receive(part(1));
      final result = p.receive(second);
      expect(result.whereType<ScaleReading>(), isEmpty);
      expect(result.whereType<ScaleMessage>().single.error, isTrue);
    }
  });
  test(
    'late duplicate history packets are ACKed without advancing progress',
    () {
      existingUser(p);
      p.receive(part(1));
      p.receive(part(2));
      final before = p.progress;
      expect(p.receive(part(1)).whereType<SendFrame>(), hasLength(1));
      expect(p.progress, before);
    },
  );
  test('invalid final history payload never triggers measurement start', () {
    existingUser(p);
    final zero = part(1)
      ..[8] = 0
      ..[9] = 0;
    p.receive(zero);
    final result = p.receive(part(2));
    expect(result.whereType<ScaleReading>(), isEmpty);
    expect(
      result.whereType<SendFrame>().any((e) => e.bytes[1] == 0x40),
      isFalse,
    );
    expect(p.phase, 'error');
  });
  test(
    'user list duplicates including final frame do not repeat profile commands',
    () {
      handshake(p);
      p.receive([0xe7, 0xf0, 0x33, 0, 1, 8]);
      p.receive(remoteUserFrame());
      final again = p.receive(remoteUserFrame());
      expect(again.whereType<SendFrame>().single.bytes[1], 0xf1);
      expect(p.phase, 'update');
    },
  );
  test('changed user count is rejected before any profile is created', () {
    handshake(p);
    p.receive([0xe7, 0xf0, 0x33, 0, 2, 8]);
    final result = p.receive(remoteUserFrame(count: 1));
    expect(result.whereType<ScaleMessage>().single.error, isTrue);
    expect(result.whereType<SendFrame>(), isEmpty);
  });
  test('missing or expired live header cannot save mixed data', () {
    ready();
    p.receive(liveFirst);
    expect(p.receive(liveLast).whereType<ScaleReading>(), isEmpty);
    p.receive(liveHeader, receivedAt: testTime);
    p.receive(liveFirst, receivedAt: testTime);
    expect(
      p
          .receive(
            liveLast,
            receivedAt: testTime.add(const Duration(seconds: 16)),
          )
          .whereType<ScaleReading>(),
      isEmpty,
    );
    p.receive(liveHeader);
    p.receive(liveFirst);
    expect(p.receive(liveLast).whereType<ScaleReading>(), hasLength(1));
  });
  test(
    'duplicate live header and data retain an intact single measurement',
    () {
      ready();
      p.receive(liveHeader);
      p.receive(liveFirst);
      p.receive(liveHeader);
      p.receive(liveFirst);
      expect(p.receive(liveLast).whereType<ScaleReading>(), hasLength(1));
      expect(p.receive(liveLast).whereType<ScaleReading>(), isEmpty);
    },
  );
  test('malformed live header discards any previously accepted owner', () {
    ready();
    p.receive(liveHeader);
    p.receive(liveFirst);
    p.receive(liveHeader.take(8).toList());
    expect(p.receive(liveLast).whereType<ScaleReading>(), isEmpty);
  });
}
