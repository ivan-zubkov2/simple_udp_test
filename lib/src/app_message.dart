import 'dart:convert';

class AppMessage {
  const AppMessage({
    required this.id,
    required this.time,
    required this.message,
  });

  final int id;
  final DateTime time;
  final String message;

  Map<String, Object> toJson() {
    return {
      'id': id,
      'time': time.toIso8601String(),
      'message': message,
    };
  }

  String toWire() => '${jsonEncode(toJson())}\n';

  factory AppMessage.fromWire(String line) {
    final decoded = jsonDecode(line);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Message must be a JSON object.');
    }

    final id = decoded['id'];
    final time = decoded['time'];
    final message = decoded['message'];

    if (id is! int) {
      throw const FormatException('Message id must be an int.');
    }
    if (time is! String) {
      throw const FormatException('Message time must be a string.');
    }
    if (message is! String) {
      throw const FormatException('Message text must be a string.');
    }

    return AppMessage(
      id: id,
      time: DateTime.parse(time),
      message: message,
    );
  }

  @override
  String toString() {
    return 'id=$id time=${time.toIso8601String()} message="$message"';
  }
}
