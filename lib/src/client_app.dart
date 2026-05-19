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
  StreamSubscription<RawSocketEvent>? _socketSubscription;
  Timer? _timer;
  bool _isSending = false;
  bool _isFlushingQueue = false;
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
      _socketSubscription = socket.listen(
        (_) {},
        onError: (Object error, StackTrace stackTrace) {
          _appendLog('UDP socket stream error: $error');
        },
        onDone: () {
          _appendLog('UDP socket closed.');
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
      _appendLog(
        'Sending UDP datagrams from ${socket.address.address}:${socket.port} to ${host.address}:$port',
      );

      _timer = Timer.periodic(Duration(milliseconds: 100), (_) {
        for (var index = 0; index < 2; index++) {
          final bytesSent = socket.send(
            utf8.encode(AppMessage(
              id: _nextId++,
              time: DateTime.now(),
              message: messageText,
            ).toWire()),
            host,
            port,
          );

          if (bytesSent == 0) {
            _appendLog(
              'Failed to send (bytes = 0) id=${_nextId} to ${host.address}:${port}',
            );
          }
        }
      });
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

  Future<void> _flushQueue() async {
    if (_isFlushingQueue) {
      return;
    }

    _isFlushingQueue = true;

    try {
      while (_socket != null && _pendingMessages.isNotEmpty) {
        final socket = _socket;
        if (socket == null) {
          break;
        }

        final pending = _pendingMessages.first;

        try {

          _pendingMessages.removeAt(0);
        } on SocketException catch (error) {
          pending.attempts++;
          _appendLog(
            'SocketException while sending id=${pending.message.id} to ${pending.host.address}:${pending.port}: $error; retry attempt ${pending.attempts}',
          );
        } catch (error) {
          pending.attempts++;
          _appendLog(
            'Failed to send id=${pending.message.id} to ${pending.host.address}:${pending.port}: $error; retry attempt ${pending.attempts}',
          );
        }
      }
    } finally {
        _isFlushingQueue = false;
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
