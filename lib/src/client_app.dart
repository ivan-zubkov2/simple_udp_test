import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

import 'app_config.dart';
import 'app_message.dart';

const _clientTargetHost = '192.168.51.235';
const _clientTargetPort = 9002;
const _clientSendInterval = Duration(milliseconds: 5);
const _clientMessage = 'Hello from client';

class ClientApp extends StatelessWidget {
  const ClientApp({super.key, required this.config});

  final AppConfig config;

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
  Timer? _timer;
  bool _isStarting = false;
  int _nextId = 0;

  @override
  void dispose() {
    _timer?.cancel();
    _socket?.close();
    _logScrollController.dispose();
    _logController.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    if (_socket != null || _isStarting) {
      return;
    }

    setState(() {
      _isStarting = true;
    });

    try {
      final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      _socket = socket;
      _logInfo(
        'Sending to $_clientTargetHost:$_clientTargetPort from ${socket.address.address}:${socket.port}',
      );

      _timer = Timer.periodic(_clientSendInterval, (_) {
        final message = AppMessage(
          id: _nextId++,
          time: DateTime.now(),
          message: _clientMessage,
        );

        final bytesSent = socket.send(
          utf8.encode(message.toWire()),
          InternetAddress(_clientTargetHost),
          _clientTargetPort,
        );

        if (bytesSent == 0) {
          _logInfo(
            'Failed to send message id=${message.id}: bytesSent == 0',
          );
        } else {
          _logInfo(
            'Sent id=${message.id} time=${message.time.toIso8601String()} message="${message.message}"',
          );
        }
      });
    } catch (error) {
      _logError('Failed to start client: $error');
    } finally {
      if (mounted) {
        setState(() {
          _isStarting = false;
        });
      }
    }
  }

  void _stop() {
    _timer?.cancel();
    _timer = null;

    final socket = _socket;
    _socket = null;
    if (socket != null) {
      socket.close();
    }

    _logInfo('UDP sender stopped.');

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
    final isRunning = _socket != null;

    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            ElevatedButton(
              onPressed:
                  _isStarting ? null : (isRunning ? _stop : _start),
              child: Text(
                _isStarting ? 'Starting...' : (isRunning ? 'Stop' : 'Start'),
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
