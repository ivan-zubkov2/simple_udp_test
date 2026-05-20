import 'dart:async';
import 'dart:convert';
import 'dart:io';

const _listenHost = '192.168.51.123';
const _targetHost = '192.168.51.123';
const _port = 9002;
const _sendInterval = Duration(milliseconds: 50);
const _messageText = 'Hello from client';

enum LaunchMode { server, client }


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


Future<void> main(List<String> args) async {
  print("TEST!!!");

  try {
    final mode = _parseMode(args);

    switch (mode) {
      case LaunchMode.server:
        await _runServer();
        return;
      case LaunchMode.client:
        await _runClient();
        return;
    }
  } on FormatException catch (error) {
    stderr.writeln(error.message);
    _printUsage();
    exitCode = 64;
  }
}

Future<void> _runServer() async {
  final listener = await RawDatagramSocket.bind(_listenHost, _port);

  stdout.writeln('Listening on $_listenHost:$_port');

  var lastReceivedId = -1;

  listener.listen((event) {
    if (event != RawSocketEvent.read) {
      return;
    }

    Datagram? datagram;
    while ((datagram = listener.receive()) != null) {
      final payload = utf8.decode(datagram!.data).trim();
      if (payload.isEmpty) {
        continue;
      }

      try {
        final message = AppMessage.fromWire(payload);
        final expectedId = lastReceivedId + 1;
        if (lastReceivedId >= 0 && message.id != expectedId) {
          print(
            'Skipped id on server: expected $expectedId, got ${message.id}',
          );
        }
          print(
            'Received id=${message.id} time=${message.time} message=${message.message}',
          );
        lastReceivedId = message.id;
      } on FormatException catch (error) {
        print('Invalid datagram payload: $error');
      }
    }
  });

  await Completer<void>().future;
}

Future<void> _runClient() async {
  final sender = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);

  print(
    'Sending to $_targetHost:$_port from ${sender.address.address}:${sender.port}',
  );

  var nextId = 0;
  Timer.periodic(_sendInterval, (_) async {
    for (var index = 0; index < 2; index++) {
      final message = AppMessage(
        id: nextId++,
        time: DateTime.now(),
        message: _messageText,
      );

      final bytesSent = sender.send(
        [0,1,2,3],
        InternetAddress(_targetHost),
        _port,
      );

      if (bytesSent == 0) {
        print('Failed to send message id=${message.id} time=${message.time}: bytesSent == 0');
        if (message.id % 2 == 0) {
          print("Even message failed");
        }
      }
    }
  });

  await Completer<void>().future;
}

LaunchMode _parseMode(List<String> args) {
  String? modeValue;

  for (var index = 0; index < args.length; index++) {
    final arg = args[index];

    if (arg == '--mode') {
      if (index + 1 >= args.length) {
        throw const FormatException('Missing value for --mode.');
      }
      modeValue = args[index + 1];
      index++;
      continue;
    }

    if (arg.startsWith('--mode=')) {
      modeValue = arg.substring('--mode='.length);
    }
  }

  if (modeValue == null) {
    return LaunchMode.client;
  }

  switch (modeValue) {
    case 'server':
      return LaunchMode.server;
    case 'client':
      return LaunchMode.client;
    default:
      throw FormatException('Invalid mode: $modeValue');
  }
}

void _printUsage() {
  stdout.writeln('Usage: dart run --mode=server');
  stdout.writeln('   or: dart run --mode=client');
}
