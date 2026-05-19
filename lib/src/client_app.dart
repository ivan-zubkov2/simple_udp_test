import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

import 'app_message.dart';

const _clientTargetHost = '127.0.0.1';
const _clientTargetPort = 9002;
const _clientSendInterval = Duration(milliseconds: 50);
const _clientMessage = 'Hello from client';

class ClientApp extends StatelessWidget {
  const ClientApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      home: _ClientScreen(),
    );
  }
}

class _ClientScreen extends StatefulWidget {
  const _ClientScreen();

  @override
  State<_ClientScreen> createState() => _ClientScreenState();
}

class _ClientScreenState extends State<_ClientScreen> {
  final TextEditingController _logController = TextEditingController();
  final ScrollController _logScrollController = ScrollController();
  RawDatagramSocket? _socket;
  StreamSubscription<RawSocketEvent>? _socketSubscription;
  Timer? _timer;
  bool _isStarting = false;
  int _nextId = 0;

  @override
  void dispose() {
    _stopSending(logStop: false);
    _logScrollController.dispose();
    _logController.dispose();
    super.dispose();
  }

  Future<void> _startSending() async {
    if (_socket != null || _isStarting) {
      return;
    }

    setState(() {
      _isStarting = true;
    });

    try {
      final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      _socket = socket;
      _socketSubscription = socket.listen(
        (_) {},
        onError: (Object error, StackTrace stackTrace) {
          _logError('UDP socket stream error: $error');
        },
        onDone: () {
          _logInfo('UDP socket closed.');
          _socket = null;
          _socketSubscription = null;
          _timer?.cancel();
          _timer = null;
          if (mounted) {
            setState(() {});
          }
        },
        cancelOnError: false,
      );
      _logInfo(
        'Sending UDP datagrams to $_clientTargetHost:$_clientTargetPort from ${socket.address.address}:${socket.port}',
      );

      _timer = Timer.periodic(_clientSendInterval, (_) {
        final message = AppMessage(
          id: _nextId++,
          time: DateTime.now(),
          message: _clientMessage,
        );

        try {
          for (var index = 0; index < 2; index++) {
            final encodedMessage = utf8.encode(message.toWire());

            final bytesSent = socket.send(
              encodedMessage,
              InternetAddress(_clientTargetHost),
              _clientTargetPort,
            );

            if (bytesSent == 0) {
              _logInfo('Failed to send message id=${message.id}: bytesSent == 0 $encodedMessage, ${encodedMessage.length}');
            } else if (message.id % 100 == 0) {
              _logInfo(
                'Sent id=${message.id} time=${message.time.toIso8601String()} message="${message.message}"',
              );
            }
          }
        } on SocketException catch (error) {
          _logError('SocketException while sending id=${message.id}: $error');
        } catch (error) {
          _logError('Unexpected send error for id=${message.id}: $error');
        }
      });
    } catch (error) {
      _logError('Failed to start sender: $error');
    } finally {
      if (mounted) {
        setState(() {
          _isStarting = false;
        });
      }
    }
  }

  void _stopSending({bool logStop = true}) {
    final subscription = _socketSubscription;
    _socketSubscription = null;
    if (subscription != null) {
      unawaited(subscription.cancel());
    }

    _timer?.cancel();
    _timer = null;

    final socket = _socket;
    _socket = null;
    if (socket != null) {
      socket.close();
    }

    if (logStop) {
      _logInfo('UDP sender stopped.');
    }

    if (mounted) {
      setState(() {});
    }
  }

  void _appendLog(String line) {
    if (!mounted) {
      return;
    }

    final existing = _logController.text;
    _logController.text = existing.isEmpty ? line : '$existing\n$line';
    _logController.selection = TextSelection.collapsed(
      offset: _logController.text.length,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_logScrollController.hasClients) {
        return;
      }
      _logScrollController.jumpTo(
        _logScrollController.position.maxScrollExtent,
      );
    });
  }

  void _logInfo(String line) {
    stdout.writeln(line);
    _appendLog(line);
  }

  void _logError(String line) {
    stderr.writeln(line);
    _appendLog(line);
  }

  @override
  Widget build(BuildContext context) {
    final isActive = _socket != null;

    return Scaffold(
      appBar: AppBar(title: const Text('Client')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ElevatedButton(
              onPressed:
                  _isStarting
                      ? null
                      : (isActive ? _stopSending : _startSending),
              child: Text(
                _isStarting
                    ? 'Starting...'
                    : (isActive ? 'Stop sending' : 'Start sending'),
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: TextField(
                controller: _logController,
                scrollController: _logScrollController,
                readOnly: true,
                expands: true,
                maxLines: null,
                textAlignVertical: TextAlignVertical.top,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
