import 'package:flutter/material.dart';

import 'src/app_config.dart';
import 'src/client_app.dart';
import 'src/server_app.dart';

void main(List<String> args) {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    final config = AppConfig.fromArgs(args);

    switch (config.mode) {
      case AppMode.server:
        runApp(const ServerApp());
        return;
      case AppMode.client:
        runApp(const ClientApp());
        return;
    }
  } on FormatException catch (error) {
    runApp(_ConfigErrorApp(message: error.message));
  }
}

class _ConfigErrorApp extends StatelessWidget {
  const _ConfigErrorApp({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('Configuration Error')),
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: SelectableText(message),
        ),
      ),
    );
  }
}
