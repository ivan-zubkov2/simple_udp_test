import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

import 'app_config.dart';
import 'app_message.dart';

const _clientTargetHost = '192.168.51.235';
const _clientTargetPort = 9002;
const _clientSendInterval = Duration(milliseconds: 50);
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
  RawDatagramSocket? _socket;
  Timer? _timer;
  bool _isStarting = false;
  int _nextId = 0;

  @override
  void dispose() {
    _timer?.cancel();
    _socket?.close();
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
      stdout.writeln(
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
          InternetAddress.loopbackIPv4,
          _clientTargetPort,
        );

        if (bytesSent == 0) {
          stdout.writeln(
            'Failed to send message id=${message.id}: bytesSent == 0',
          );
        } else {
          stdout.writeln(
            'Sent id=${message.id} time=${message.time.toIso8601String()} message="${message.message}"',
          );
        }
      });
    } catch (error) {
      stderr.writeln('Failed to start client: $error');
    } finally {
      if (mounted) {
        setState(() {
          _isStarting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final canStart = _socket == null && !_isStarting;

    return Scaffold(
      body: Center(
        child: ElevatedButton(
          onPressed: canStart ? _start : null,
          child: Text(_isStarting ? 'Starting...' : 'Start'),
        ),
      ),
    );
  }
}
