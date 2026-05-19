import 'dart:io';

const String _defaultMode = String.fromEnvironment(
  'MODE',
  defaultValue: 'server',
);
const String _defaultHost = String.fromEnvironment(
  'HOST',
  defaultValue: '127.0.0.1',
);
const int _defaultPort = int.fromEnvironment('PORT', defaultValue: 9000);
const String _defaultMessage = String.fromEnvironment(
  'MESSAGE',
  defaultValue: 'Hello from client',
);
const int _defaultIntervalMs = int.fromEnvironment(
  'INTERVAL_MS',
  defaultValue: 50,
);

enum AppMode { server, client }

class AppConfig {
  const AppConfig({
    required this.mode,
    required this.host,
    required this.port,
    required this.message,
    required this.interval,
  });

  final AppMode mode;
  final InternetAddress host;
  final int port;
  final String message;
  final Duration interval;

  factory AppConfig.fromArgs(List<String> args) {
    final options = _ParsedArgs.from(args);
    final modeValue = options.mode ?? _defaultMode;
    final hostValue = options.options['host'] ?? _defaultHost;
    final portValue = options.options['port'] ?? _defaultPort.toString();
    final messageValue = options.options['message'] ?? _defaultMessage;
    final intervalValue =
        options.options['interval-ms'] ?? _defaultIntervalMs.toString();

    final host = InternetAddress.tryParse(hostValue);
    if (host == null) {
      throw FormatException('Invalid IP address: $hostValue');
    }

    final port = int.tryParse(portValue);
    if (port == null || port < 1 || port > 65535) {
      throw FormatException('Port must be between 1 and 65535.');
    }

    final intervalMs = int.tryParse(intervalValue);
    if (intervalMs == null || intervalMs < 1) {
      throw FormatException('Interval must be a positive number of ms.');
    }

    return AppConfig(
      mode: _parseMode(modeValue),
      host: host,
      port: port,
      message: messageValue,
      interval: Duration(milliseconds: intervalMs),
    );
  }

  static AppMode _parseMode(String value) {
    switch (value.toLowerCase()) {
      case 'server':
        return AppMode.server;
      case 'client':
        return AppMode.client;
      default:
        throw FormatException('Mode must be either "server" or "client".');
    }
  }
}

class _ParsedArgs {
  const _ParsedArgs({
    required this.mode,
    required this.options,
  });

  final String? mode;
  final Map<String, String> options;

  factory _ParsedArgs.from(List<String> args) {
    String? mode;
    final options = <String, String>{};

    for (var index = 0; index < args.length; index++) {
      final arg = args[index];
      if (!arg.startsWith('--')) {
        mode ??= arg;
        continue;
      }

      final parts = arg.substring(2).split('=');
      final key = parts.first;
      final inlineValue = parts.length > 1 ? parts.sublist(1).join('=') : null;
      final nextValue = index + 1 < args.length ? args[index + 1] : null;

      if (inlineValue != null) {
        options[key] = inlineValue;
        continue;
      }

      if (nextValue == null || nextValue.startsWith('--')) {
        throw FormatException('Missing value for --$key.');
      }

      options[key] = nextValue;
      index++;
    }

    final modeOption = options['mode'];
    if (modeOption != null) {
      mode = modeOption;
    }

    return _ParsedArgs(mode: mode, options: options);
  }
}
