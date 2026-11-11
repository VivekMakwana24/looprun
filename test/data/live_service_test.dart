import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:looprun/data/models/models.dart';
import 'package:looprun/data/services/live_service.dart';

/// Real sockets on loopback: these tests prove what the fake cannot (first-message auth, socket closed on cancel).
void main() {
  late HttpServer server;
  late List<Uri> requests;
  late List<WebSocket> serverSockets;
  late List<String> received; // frames the server got from the client
  late Completer<void> firstFrame;
  late Completer<void> clientClosed;

  SocketLiveService service({Duration connectTimeout = const Duration(seconds: 5)}) =>
      SocketLiveService(
        baseUrl: 'http://127.0.0.1:${server.port}',
        connectTimeout: connectTimeout,
      );

  setUp(() async {
    requests = [];
    serverSockets = [];
    received = [];
    firstFrame = Completer<void>();
    clientClosed = Completer<void>();
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((req) async {
      requests.add(req.uri);
      final ws = await WebSocketTransformer.upgrade(req);
      serverSockets.add(ws);
      ws.listen(
        (m) {
          received.add(m as String);
          if (!firstFrame.isCompleted) firstFrame.complete();
        },
        onDone: () {
          if (!clientClosed.isCompleted) clientClosed.complete();
        },
      );
    });
  });

  tearDown(() async {
    for (final s in serverSockets) {
      await s.close();
    }
    await server.close(force: true);
  });

  test('the first frame is the auth message and the token is not in the URL', () async {
    final sub = service().connect(bbox: '1,2,3,4', token: 'secret-token').listen((_) {});
    await firstFrame.future.timeout(const Duration(seconds: 5));

    expect(jsonDecode(received.first), {'type': 'auth', 'token': 'secret-token'});
    expect(requests.single.path, '/v1/live');
    expect(requests.single.queryParameters['bbox'], '1,2,3,4');
    expect(requests.single.toString().contains('secret-token'), isFalse);
    expect(requests.single.queryParameters.containsKey('token'), isFalse);
    await sub.cancel();
  });

  test('cell_changed frames arrive as CellChange, junk is skipped', () async {
    final changes = <CellChange>[];
    final got = Completer<void>();
    final sub = service().connect(bbox: 'b', token: 't').listen((c) {
      changes.add(c);
      got.complete();
    });
    await firstFrame.future.timeout(const Duration(seconds: 5));
    serverSockets.single.add('not json');
    serverSockets.single.add(jsonEncode({'type': 'hello'}));
    serverSockets.single.add(jsonEncode({
      'type': 'cell_changed',
      'cell': '8a1',
      'lat': 50.1,
      'lng': 8.6,
      'owner': {'id': 'u1', 'name': 'Ann'},
      'mine': false,
    }));
    await got.future.timeout(const Duration(seconds: 5));
    expect(changes.single.id, '8a1');
    expect(changes.single.owner!.name, 'Ann');
    await sub.cancel();
  });

  test('cancelling the subscription closes the socket at once, with no frame from the server', () async {
    final sub = service().connect(bbox: 'b', token: 't').listen((_) {});
    await firstFrame.future.timeout(const Duration(seconds: 5));
    expect(clientClosed.isCompleted, isFalse);

    await sub.cancel();
    await clientClosed.future.timeout(const Duration(seconds: 3));
    expect(clientClosed.isCompleted, isTrue);
  });

  test('cancelling before the socket is open does not leave one behind', () async {
    final sub = service().connect(bbox: 'b', token: 't').listen((_) {});
    await sub.cancel(); // immediately, while still connecting
    // If the connect still completes, the service must close that socket.
    await Future<void>.delayed(const Duration(milliseconds: 500));
    for (final s in serverSockets) {
      expect(s.readyState == WebSocket.closed || s.readyState == WebSocket.closing, isTrue);
    }
  });

  test('a server close with code 4401 becomes LiveClosedException(4401)', () async {
    final errors = <Object>[];
    final done = Completer<void>();
    final sub = service().connect(bbox: 'b', token: 't').listen(
      (_) {},
      onError: errors.add,
      onDone: done.complete,
    );
    await firstFrame.future.timeout(const Duration(seconds: 5));
    await serverSockets.single.close(4401, 'bad token');
    await done.future.timeout(const Duration(seconds: 5));

    final e = errors.single as LiveClosedException;
    expect(e.code, 4401);
    expect(e.isAuthFailure, isTrue);
    await sub.cancel();
  });

  test('the connect timeout fails the stream and closes the half-open connection', () async {
    // A server that accepts TCP but never answers the WebSocket upgrade.
    final silent = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final accepted = <Socket>[];
    final clientGone = Completer<void>();
    silent.listen((s) {
      accepted.add(s);
      s.listen((_) {}, onDone: () {
        if (!clientGone.isCompleted) clientGone.complete();
      }, onError: (Object _) {
        if (!clientGone.isCompleted) clientGone.complete();
      });
    });

    final svc = SocketLiveService(
      baseUrl: 'http://127.0.0.1:${silent.port}',
      connectTimeout: const Duration(milliseconds: 300),
    );
    final errors = <Object>[];
    final done = Completer<void>();
    svc.connect(bbox: 'b', token: 't').listen((_) {}, onError: errors.add, onDone: done.complete);

    await done.future.timeout(const Duration(seconds: 5));
    expect(errors.single, isA<TimeoutException>());
    await clientGone.future.timeout(const Duration(seconds: 3));
    for (final s in accepted) {
      s.destroy();
    }
    await silent.close();
  });
}
