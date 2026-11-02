import 'package:healthcoach/domain/models.dart';
import 'package:healthcoach/bluetooth/sanitas_protocol.dart';

final testTime = DateTime(2026, 10, 30, 8);
Profile testProfile({String id = 'profile-1', String? remote}) => Profile(
  id: id,
  name: 'Testperson',
  initials: 'TST',
  sex: 'male',
  birthday: DateTime(1995, 6, 15),
  heightCm: 180,
  activity: 2,
  goalKg: 75,
  trackingSince: DateTime(2026, 10, 1),
  remoteId: remote,
);

List<int> measurementPacket({
  DateTime? time,
  bool flag = false,
  bool body = true,
}) {
  final bytes = timeBytes(time ?? testTime).toList();
  if (flag) bytes[0] |= 0x80;
  for (final v in [
    1600,
    if (body) 510 else 0,
    if (body) 215 else 0,
    if (body) 572 else 0,
    if (body) 401 else 0,
    if (body) 64 else 0,
    if (body) 1780 else 0,
    if (body) 2670 else 0,
    if (body) 247 else 0,
  ]) {
    bytes.addAll([v >> 8, v & 255]);
  }
  return bytes;
}

void handshake(SanitasProtocol protocol) {
  protocol.start();
  protocol.receive([0xe6, 0, 0x20]);
  protocol.receive([0xe7, 0xf0, 0x4f, 0, 90, 20, 20, 1, 0, 0, 0, 1]);
}

List<int> remoteUserFrame({
  String id = '0000000000000065',
  String name = 'TST',
  int count = 1,
  int index = 1,
  int year = 1995,
}) => [
  0xe7,
  0x34,
  count,
  index,
  ...idBytes(id),
  ...name.codeUnits,
  year - 1900,
];

List<int> detailsFrame({int day = 15, int height = 180}) => [
  0xe7,
  0xf0,
  0x36,
  0,
  ...'TST'.codeUnits,
  95,
  5,
  day,
  height,
  0x82,
];

void existingUser(SanitasProtocol protocol) {
  handshake(protocol);
  protocol.receive([0xe7, 0xf0, 0x33, 0, 1, 8]);
  protocol.receive(remoteUserFrame());
  protocol.receive(detailsFrame());
}
