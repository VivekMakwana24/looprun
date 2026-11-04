import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../models/models.dart';

/// The /live socket closed. [code] is the WebSocket close code (4401 = auth failed, 4429 = too many sockets).
class LiveClosedException implements Exception {
  const LiveClosedException(this.code);
  final int? code;

  bool get isAuthFailure => code == 4401;

  @override
  String toString() => 'LiveClosedException($code)';
}

/// WebSocket /v1/live (docs/CONTRACT.openapi.yaml). One call, one socket.
abstract class LiveService {
  /// Connects, sends {"type":"auth","token":...} as the first message, then yields `cell_changed` frames.
  /// The stream ends with a [LiveClosedException] error when the server closes the socket.
  /// Cancelling the subscription closes the socket.
  Stream<CellChange> connect({required String bbox, required String token});
}

class SocketLiveService implements LiveService {
  SocketLiveService({
    required this.baseUrl,
    this.connectTimeout = const Duration(seconds: 15),
    this.pingInterval = const Duration(seconds: 30),
  });

  /// Server origin, e.g. http://10.0.2.2:8000 (the scheme becomes ws or wss).
  final String baseUrl;

  /// Covers the TCP connect and the WebSocket upgrade. A socket that opens after the timeout is closed.
  final Duration connectTimeout;

  /// Client pings, so a half-open connection (network switch) is noticed.
  final Duration pingInterval;

  Uri _uri(String bbox) {
    final base = Uri.parse(baseUrl);
    return Uri(
      scheme: base.scheme == 'https' ? 'wss' : 'ws',
      host: base.host,
      port: base.hasPort ? base.port : null,
      path: '/v1/live',
      queryParameters: {'bbox': bbox},
    );
  }

  /// Built on a StreamController, not an async* generator: cancelling the subscription runs [onCancel]
  /// at once and closes the socket, even when no frame ever arrives.
  @override
  Stream<CellChange> connect({required String bbox, required String token}) {
    final controller = StreamController<CellChange>();
    WebSocket? socket;
    StreamSubscription<dynamic>? socketSub;
    HttpClient? client;
    var cancelled = false;

    Future<void> shutdown() async {
      cancelled = true;
      final sub = socketSub;
      final s = socket;
      socketSub = null;
      socket = null;
      try {
        await sub?.cancel();
      } catch (_) {}
      try {
        await s?.close();
      } catch (_) {}
      client?.close(force: true);
    }

    Future<void> run() async {
      client = HttpClient()..connectionTimeout = connectTimeout;
      final connecting = WebSocket.connect(_uri(bbox).toString(), customClient: client);
      final WebSocket s;
      try {
        s = await connecting.timeout(connectTimeout);
      } catch (e) {
        // A connect that finishes after the timeout must not stay open.
        unawaited(connecting.then<void>((w) => w.close(), onError: (Object _) {}));
        client?.close(force: true);
        if (!cancelled && !controller.isClosed) {
          controller.addError(e);
          await controller.close();
        }
        return;
      }
      if (cancelled) {
        unawaited(s.close());
        client?.close(force: true);
        return;
      }
      socket = s;
      s.pingInterval = pingInterval;
      // The token goes in the first message, not in the URL, so it stays out of proxy and access logs.
      s.add(jsonEncode({'type': 'auth', 'token': token}));
      socketSub = s.listen(
        (message) {
          if (cancelled || message is! String) return;
          Object? decoded;
          try {
            decoded = jsonDecode(message);
          } catch (_) {
            return;
          }
          final change = CellChange.tryParse(decoded);
          if (change != null) controller.add(change);
        },
        onError: (Object e) {
          if (cancelled || controller.isClosed) return;
          controller.addError(e);
        },
        onDone: () async {
          if (cancelled || controller.isClosed) return;
          controller.addError(LiveClosedException(s.closeCode));
          await controller.close();
        },
      );
    }

    controller.onListen = () {
      unawaited(run());
    };
    controller.onCancel = shutdown;
    return controller.stream;
  }
}
