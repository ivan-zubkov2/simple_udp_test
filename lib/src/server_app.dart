import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

import 'app_config.dart';
import 'app_message.dart';

const _serverHost = '0.0.0.0';
const _serverPort = 9002;

class ServerApp extends StatelessWidget {
  const ServerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      home: _ServerScreen(),
    );
  }
}

class _ServerScreen extends StatefulWidget {
  const _ServerScreen();

  @override
  State<_ServerScreen> createState() => _ServerScreenState();
}

class _ServerScreenState extends State<_ServerScreen> {
  final Map<String, int> _lastReceivedIds = <String, int>{};
  RawDatagramSocket? _socket;
  StreamSubscription<RawSocketEvent>? _socketSubscription;
  bool _isStarting = false;

  @override
  void dispose() {
    final subscription = _socketSubscription;
    if (subscription != null) {
      unawaited(subscription.cancel());
    }

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
      final socket = await RawDatagramSocket.bind(_serverHost, _serverPort);
      _socket = socket;
      stdout.writeln('Listening on $_serverHost:$_serverPort');
      _socketSubscription = socket.listen(
        _handleSocketEvent,
        onError: (Object error, StackTrace stackTrace) {
          stderr.writeln('UDP listener error: $error');
        },
        onDone: () {
          stdout.writeln('UDP listener stopped.');
          _socket = null;
          _socketSubscription = null;
          _lastReceivedIds.clear();
          if (mounted) {
            setState(() {});
          }
        },
        cancelOnError: true,
      );
    } catch (error) {
      stderr.writeln('Failed to start server: $error');
    } finally {
      if (mounted) {
        setState(() {
          _isStarting = false;
        });
      }
    }
  }

  void _handleSocketEvent(RawSocketEvent event) {
    if (event != RawSocketEvent.read) {
      return;
    }

    final socket = _socket;
    if (socket == null) {
      return;
    }

    Datagram? datagram;
    while ((datagram = socket.receive()) != null) {
      final currentDatagram = datagram!;
      final remoteAddress =
          '${currentDatagram.address.address}:${currentDatagram.port}';

      try {
        final payload = utf8.decode(currentDatagram.data).trim();
        if (payload.isEmpty) {
          continue;
        }

        final message = AppMessage.fromWire(payload);
        final lastReceivedId = _lastReceivedIds[remoteAddress];
        final expectedId = lastReceivedId == null ? null : lastReceivedId + 1;
        if (expectedId != null && message.id != expectedId) {
          stdout.writeln(
            'Skipped id on server [$remoteAddress]: expected $expectedId, got ${message.id}',
          );
        }
        _lastReceivedIds[remoteAddress] = message.id;
        stdout.writeln(
          'Received id=${message.id} time=${message.time.toIso8601String()} message="${message.message}"',
        );
      } on FormatException catch (error) {
        stderr.writeln('Invalid message from $remoteAddress: $error');
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
