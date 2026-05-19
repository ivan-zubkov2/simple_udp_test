import 'package:flutter_test/flutter_test.dart';
import 'package:simple_udp_test/src/app_config.dart';
import 'package:simple_udp_test/src/app_message.dart';

void main() {
  test('parses server mode', () {
    final config = AppConfig.fromArgs(['--mode=server']);

    expect(config.mode, AppMode.server);
  });

  test('round-trips a wire message', () {
    final original = AppMessage(
      id: 7,
      time: DateTime.parse('2026-05-15T10:11:12.000Z'),
      message: 'hello',
    );

    final decoded = AppMessage.fromWire(original.toWire().trim());

    expect(decoded.id, original.id);
    expect(decoded.time.toUtc(), original.time.toUtc());
    expect(decoded.message, original.message);
  });
}
