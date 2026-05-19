enum AppMode { server, client }

class AppConfig {
  const AppConfig({required this.mode});

  final AppMode mode;

  factory AppConfig.fromArgs(List<String> args) {
    String? modeValue;

    for (var index = 0; index < args.length; index++) {
      final arg = args[index];

      if (arg == '--mode') {
        if (index + 1 >= args.length) {
          throw const FormatException('Missing value for --mode.');
        }
        modeValue = args[index + 1];
        index++;
        continue;
      }

      if (arg.startsWith('--mode=')) {
        modeValue = arg.substring('--mode='.length);
        continue;
      }

      throw FormatException('Unsupported argument: $arg');
    }

    switch (modeValue) {
      case 'server':
        return const AppConfig(mode: AppMode.server);
      case 'client':
        return const AppConfig(mode: AppMode.client);
      case null:
        return const AppConfig(mode: AppMode.server);
      default:
        throw FormatException('Invalid mode: $modeValue');
    }
  }
}
