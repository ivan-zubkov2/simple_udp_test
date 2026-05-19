import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_config.dart';
import 'app_message.dart';
import 'searchable_log_view.dart';

class ClientApp extends StatelessWidget {
  const ClientApp({super.key, required this.config});

  final AppConfig config;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: _ClientScreen(config: config),
    );
  }
}

class _ClientScreen extends StatefulWidget {
  const _ClientScreen({required this.config});

  final AppConfig config;

  @override
  State<_ClientScreen> createState() => _ClientScreenState();
}

class _ClientScreenState extends State<_ClientScreen> {
  final GlobalKey<SearchableLogViewState> _logViewKey =
      GlobalKey<SearchableLogViewState>();
  final TextEditingController _logController = TextEditingController();
  final ScrollController _logScrollController = ScrollController();
  late final TextEditingController _hostController;
  late final TextEditingController _portController;
  late final TextEditingController _messageController;
  final List<_PendingDatagram> _pendingMessages = <_PendingDatagram>[];
  RawDatagramSocket? _socket;
  Timer? _timer;
  bool _isSending = false;
  bool _isFlushingQueue = false;
  int _sendSession = 0;
  int _nextId = 0;

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
    _stopSending(logStop: false);

    _hostController.dispose();
    _portController.dispose();
    _messageController.dispose();
    _logScrollController.dispose();
    _logController.dispose();
    super.dispose();
  }

  Future<void> _startSending() async {
    if (_socket != null || _isSending) {
      return;
    }

    setState(() {
      _isSending = true;
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

      final messageText = _messageController.text;
      final bindAddress =
          host.type == InternetAddressType.IPv6
              ? InternetAddress.anyIPv6
              : InternetAddress.anyIPv4;
      final socket = await RawDatagramSocket.bind(bindAddress, 0);
      _socket = socket;
      final session = ++_sendSession;
      _appendLog(
        'Sending UDP datagrams from ${socket.address.address}:${socket.port} to ${host.address}:$port',
      );

      _timer = Timer.periodic(widget.config.interval, (_) {
        for (var index = 0; index < 2; index++) {
          _pendingMessages.add(
            _PendingDatagram(
              host: host,
              port: port,
              message: AppMessage(
                id: _nextId++,
                time: DateTime.now(),
                message: messageText,
              ),
            ),
          );
        }
        unawaited(_flushQueue(session));
      });

      unawaited(_flushQueue(session));
    } catch (error) {
      _appendLog('Failed to start sender: $error');
    } finally {
      if (mounted) {
        setState(() {
          _isSending = false;
        });
      }
    }
  }

  Future<void> _flushQueue(int session) async {
    if (_isFlushingQueue) {
      return;
    }

    _isFlushingQueue = true;

    try {
      while (_sendSession == session && _socket != null && _pendingMessages.isNotEmpty) {
        final socket = _socket;
        if (socket == null || _sendSession != session) {
          break;
        }

        final pending = _pendingMessages.first;

        try {
          final bytesSent = socket.send(
            utf8.encode(pending.message.toWire()),
            pending.host,
            pending.port,
          );

          if (bytesSent == 0) {
            pending.attempts++;
            _appendLog(
              'Failed to send (bytes = 0) id=${pending.message.id} to ${pending.host.address}:${pending.port}; retry attempt ${pending.attempts}',
            );
            await Future<void>.delayed(widget.config.interval);
            continue;
          }

          if (pending.attempts > 0) {
            _appendLog(
              'Retry succeeded for id=${pending.message.id} after ${pending.attempts} failure(s)',
            );
          }
          _appendLog(
            'Sent id=${pending.message.id} time=${pending.message.time.toIso8601String()} message="${pending.message.message}"',
          );
          _pendingMessages.removeAt(0);
        } catch (error) {
          pending.attempts++;
          _appendLog(
            'Failed to send id=${pending.message.id} to ${pending.host.address}:${pending.port}: $error; retry attempt ${pending.attempts}',
          );
          await Future<void>.delayed(widget.config.interval);
        }
      }
    } finally {
      if (_sendSession == session) {
        _isFlushingQueue = false;
      }
    }
  }

  void _stopSending({bool logStop = true}) {
    _sendSession++;
    _timer?.cancel();
    _timer = null;
    _pendingMessages.clear();
    _isFlushingQueue = false;

    final socket = _socket;
    if (socket != null) {
      socket.close();
      _socket = null;
    }

    if (logStop) {
      _appendLog('UDP sender stopped.');
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

  @override
  Widget build(BuildContext context) {
    final isActive = _socket != null;
    final canStart = !isActive && !_isSending;

    return Scaffold(
      appBar: AppBar(title: const Text('Client')),
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
                      labelText: 'Message',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton(
                    onPressed:
                        _isSending
                            ? null
                            : (isActive ? _stopSending : _startSending),
                    child: Text(
                      _isSending
                          ? 'Starting...'
                          : (isActive ? 'Stop sending' : 'Start sending'),
                    ),
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

class _PendingDatagram {
  _PendingDatagram({
    required this.host,
    required this.port,
    required this.message,
  });

  final InternetAddress host;
  final int port;
  final AppMessage message;
  int attempts = 0;
}
