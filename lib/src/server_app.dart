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
  final TextEditingController _logController = TextEditingController();
  final ScrollController _logScrollController = ScrollController();
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
      final socket = await RawDatagramSocket.bind(_serverHost, _serverPort);
      _socket = socket;
      _logInfo('Listening on $_serverHost:$_serverPort');
      _socketSubscription = socket.listen(
        _handleSocketEvent,
        onError: (Object error, StackTrace stackTrace) {
          _logError('UDP listener error: $error');
        },
        onDone: () {
          _logInfo('UDP listener stopped.');
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
      _logError('Failed to start server: $error');
    } finally {
      if (mounted) {
        setState(() {
          _isStarting = false;
        });
      }
    }
  }

  Future<void> _stop() async {
    final subscription = _socketSubscription;
    _socketSubscription = null;
    if (subscription != null) {
      await subscription.cancel();
    }

    final socket = _socket;
    _socket = null;
    if (socket != null) {
      socket.close();
    }

    _lastReceivedIds.clear();
    _logInfo('UDP listener stopped.');

    if (mounted) {
      setState(() {});
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
          _logInfo(
            'Skipped id on server [$remoteAddress]: expected $expectedId, got ${message.id}',
          );
        }
        _lastReceivedIds[remoteAddress] = message.id;
        _logInfo(
          'Received id=${message.id} time=${message.time.toIso8601String()} message="${message.message}"',
        );
      } on FormatException catch (error) {
        _logError('Invalid message from $remoteAddress: $error');
      }
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
