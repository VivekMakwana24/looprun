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
  SocketLiveService({required this.baseUrl});

  /// Server origin, e.g. http://10.0.2.2:8000 (the scheme becomes ws or wss).
  final String baseUrl;

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

  @override
  Stream<CellChange> connect({required String bbox, required String token}) async* {
    final socket = await WebSocket.connect(_uri(bbox).toString()).timeout(const Duration(seconds: 15));
    try {
      // The token goes in the first message, not in the URL, so it stays out of proxy and access logs.
      socket.add(jsonEncode({'type': 'auth', 'token': token}));
      await for (final message in socket) {
        if (message is! String) continue;
        Object? decoded;
        try {
          decoded = jsonDecode(message);
        } catch (_) {
          continue;
        }
        final change = CellChange.tryParse(decoded);
        if (change != null) yield change;
      }
      throw LiveClosedException(socket.closeCode);
    } finally {
      await socket.close();
    }
  }
}
