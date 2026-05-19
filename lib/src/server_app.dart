import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_config.dart';
import 'app_message.dart';
import 'searchable_log_view.dart';

class ServerApp extends StatelessWidget {
  const ServerApp({super.key, required this.config});

  final AppConfig config;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: _ServerScreen(config: config),
    );
  }
}

class _ServerScreen extends StatefulWidget {
  const _ServerScreen({required this.config});

  final AppConfig config;

  @override
  State<_ServerScreen> createState() => _ServerScreenState();
}

class _ServerScreenState extends State<_ServerScreen> {
  final GlobalKey<SearchableLogViewState> _logViewKey =
      GlobalKey<SearchableLogViewState>();
  final TextEditingController _logController = TextEditingController();
  final ScrollController _logScrollController = ScrollController();
  late final TextEditingController _hostController;
  late final TextEditingController _portController;
  late final TextEditingController _messageController;
  final Map<String, int> _lastReceivedIds = <String, int>{};
  RawDatagramSocket? _socket;
  StreamSubscription<RawSocketEvent>? _socketSubscription;
  bool _isStarting = false;

  @override
  void initState() {
    super.initState();
    _hostController = TextEditingController(
      text: widget.config.host.address,
    );
    _portController = TextEditingController(
      text: widget.config.port.toString(),
    );
    _messageController = TextEditingController(
      text: widget.config.message,
    );
  }

  @override
  void dispose() {
    final socketSubscription = _socketSubscription;
    if (socketSubscription != null) {
      unawaited(socketSubscription.cancel());
    }

    final socket = _socket;
    if (socket != null) {
      socket.close();
    }
    _hostController.dispose();
    _portController.dispose();
    _messageController.dispose();
    _logScrollController.dispose();
    _logController.dispose();
    super.dispose();
  }

  Future<void> _startServer() async {
    if (_socket != null || _isStarting) {
      return;
    }

    setState(() {
      _isStarting = true;
    });

    try {
      final host = InternetAddress.tryParse(_hostController.text.trim());
      if (host == null) {
        throw const FormatException('Enter a valid IP address.');
      }

      final port = int.tryParse(_portController.text.trim());
      if (port == null || port < 1 || port > 65535) {
        throw const FormatException('Enter a port between 1 and 65535.');
      }

      final socket = await RawDatagramSocket.bind(
        host,
        port,
      );
      _socket = socket;
      _appendLog(
        'UDP listener started on ${socket.address.address}:${socket.port}',
      );
      _socketSubscription = socket.listen(
        _handleSocketEvent,
        onError: (Object error, StackTrace stackTrace) {
          _appendLog('UDP listener error: $error');
        },
        onDone: () {
          _appendLog('UDP listener stopped.');
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
      _appendLog('Failed to start server: $error');
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
        final line = utf8.decode(currentDatagram.data).trim();
        if (line.isEmpty) {
          continue;
        }

        final message = AppMessage.fromWire(line);
        final lastReceivedId = _lastReceivedIds[remoteAddress];
        final expectedId = lastReceivedId == null ? null : lastReceivedId + 1;
        if (expectedId != null && message.id != expectedId) {
          _appendLog(
            'ERROR [$remoteAddress] expected id=$expectedId but received id=${message.id}',
          );
        }
        _lastReceivedIds[remoteAddress] = message.id;
        _appendLog(
          '[$remoteAddress] id=${message.id} time=${message.time.toIso8601String()}',
        );
      } on FormatException catch (error) {
        _appendLog('Invalid message from $remoteAddress: $error');
      } catch (error) {
        _appendLog('Datagram error from $remoteAddress: $error');
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

  @override
  Widget build(BuildContext context) {
    final canStart = _socket == null && !_isStarting;

    return Scaffold(
      appBar: AppBar(title: const Text('Server')),
      body: Shortcuts(
        shortcuts: const <ShortcutActivator, Intent>{
          SingleActivator(LogicalKeyboardKey.keyF, control: true):
              SearchIntent(),
        },
        child: Actions(
          actions: <Type, Action<Intent>>{
            SearchIntent: CallbackAction<SearchIntent>(
              onInvoke: (SearchIntent intent) {
                _logViewKey.currentState?.openSearch();
                return null;
              },
            ),
          },
          child: Focus(
            autofocus: true,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: _hostController,
                    enabled: canStart,
                    decoration: const InputDecoration(
                      labelText: 'IP address',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _portController,
                    enabled: canStart,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Port',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _messageController,
                    enabled: canStart,
                    decoration: const InputDecoration(
                      labelText: 'Message (unused in server mode)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton(
                    onPressed: canStart ? _startServer : null,
                    child: Text(_isStarting ? 'Starting...' : 'Start listener'),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: SearchableLogView(
                      key: _logViewKey,
                      controller: _logController,
                      scrollController: _logScrollController,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
