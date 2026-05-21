import 'dart:async';
import 'dart:io';

const _targetHost = '127.0.0.1';
const _port = 9002;
const _sendInterval = Duration(milliseconds: 50);


Future<void> main(List<String> args) async {
  await _runClient();
}

Future<void> _runClient() async {
  final sender = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);

  print(
    'Sending to $_targetHost:$_port from ${sender.address.address}:${sender.port}',
  );

  var nextId = 0;
  Timer.periodic(_sendInterval, (_) async {
    for (var index = 0; index < 2; index++) {
      final messageID = nextId++;
      final messageTime = DateTime.now();

      final bytesSent = sender.send(
        [0,1,2,3],
        InternetAddress(_targetHost),
        _port,
      );

      if (bytesSent == 0) {
        print('Failed to send message id=$messageID time=$messageTime: bytesSent == 0');
        if (messageID % 2 == 0) {
          print("Even message failed");
        }
      }
    }
  });

  await Completer<void>().future;
}
