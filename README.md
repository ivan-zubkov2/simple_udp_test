# simple_udp_test

Simple socket test app with two modes:

- `server`: binds a UDP listener to an IP/port and prints every received message
- `client`: sends UDP messages to a target IP/port every 50 ms

Each message is sent as newline-delimited JSON with this structure:

- `id`: `int`
- `time`: ISO-8601 `DateTime`
- `message`: `String`

Examples:

```bash
flutter run -d windows --dart-define=MODE=server --dart-define=HOST=127.0.0.1 --dart-define=PORT=9000
```

```bash
flutter run -d windows --dart-define=MODE=client --dart-define=HOST=127.0.0.1 --dart-define=PORT=9000 --dart-define=MESSAGE=hello
```

Build an MSIX package:

```bash
flutter pub get
flutter build windows --release
dart run msix:create
```
