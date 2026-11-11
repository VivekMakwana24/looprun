import 'package:flutter_test/flutter_test.dart';
import 'package:looprun/data/models/api_exception.dart';
import 'package:looprun/data/models/models.dart';
import 'package:looprun/data/repositories/cell_repository.dart';
import 'package:looprun/data/services/live_service.dart';
import 'package:looprun/data/upload/backoff.dart';

import '../fakes/fakes.dart';

void main() {
  late FakeApiService api;
  late FakeLiveService live;
  late CellRepository repo;
  String? token = 'tok';

  const mine = Cell(id: 'a', lat: 50.0, lng: 8.7, owner: UserRef(id: 'u1', name: 'me'), mine: true);
  const other = Cell(id: 'b', lat: 50.001, lng: 8.7, owner: UserRef(id: 'u2', name: 'bob'));

  setUp(() {
    token = 'tok';
    api = FakeApiService()..cells = [mine, other];
    live = FakeLiveService();
    repo = CellRepository(
      api: api,
      live: live,
      tokenProvider: () => token,
      reconnectPolicy: const BackoffPolicy(
        base: Duration(milliseconds: 5),
        max: Duration(milliseconds: 20),
      ),
    );
  });

  tearDown(() async {
    await repo.dispose();
  });

  test('loadArea replaces the cache and publishes it', () async {
    final seen = <int>[];
    final sub = repo.updates.listen((l) => seen.add(l.length));
    final cells = await repo.loadArea('8.6,49.9,8.8,50.1');
    await settle();
    expect(cells.length, 2);
    expect(repo.snapshot.length, 2);
    expect(seen, [2]);
    expect(api.bboxes, ['8.6,49.9,8.8,50.1']);
    await sub.cancel();
  });

  test('a failed load keeps the old cache', () async {
    await repo.loadArea('x');
    api.cellsError = const ApiException(429, 'slow down');
    await expectLater(repo.loadArea('y'), throwsA(isA<ApiException>()));
    expect(repo.snapshot.length, 2);
  });

  test('nearestCell picks the closest cell within range', () async {
    await repo.loadArea('x');
    expect(repo.nearestCell(50.00001, 8.7)!.id, 'a');
    expect(repo.nearestCell(50.00099, 8.7)!.id, 'b');
    expect(repo.nearestCell(51.0, 9.0), isNull);
  });

  test('startLive connects with the token and applies cell_changed frames', () async {
    await repo.loadArea('x');
    repo.startLive('1,2,3,4');
    expect(live.bboxes, ['1,2,3,4']);
    expect(live.tokens, ['tok']);
    live.latest.add(const CellChange(
      id: 'c',
      lat: 50.002,
      lng: 8.7,
      owner: UserRef(id: 'u3', name: 'cy'),
      mine: false,
    ));
    // Owner changes for an existing cell.
    live.latest.add(const CellChange(
      id: 'b',
      lat: 50.001,
      lng: 8.7,
      owner: UserRef(id: 'u1', name: 'me'),
      mine: true,
    ));
    await settle();
    final byId = {for (final c in repo.snapshot) c.id: c};
    expect(byId.length, 3);
    expect(byId['c']!.owner!.name, 'cy');
    expect(byId['b']!.mine, isTrue);
  });

  test('a change without owner is shown as private', () async {
    repo.startLive('1,2,3,4');
    live.latest.add(const CellChange(id: 'z', lat: 1, lng: 2, owner: null, mine: false));
    await settle();
    expect(repo.snapshot.single.hidden, isTrue);
  });

  test('startLive with the same box does not reconnect, another box does', () async {
    repo.startLive('1,2,3,4');
    repo.startLive('1,2,3,4');
    expect(live.sockets.length, 1);
    repo.startLive('5,6,7,8');
    expect(live.sockets.length, 2);
    expect(live.bboxes.last, '5,6,7,8');
  });

  test('a dropped socket is reopened after a delay', () async {
    repo.startLive('1,2,3,4');
    live.latest.addError(const LiveClosedException(1006));
    await settle(80);
    expect(live.sockets.length, 2);
    expect(repo.liveWanted, isTrue);
  });

  test('after a reconnect the area is fetched again to catch up on missed changes', () async {
    await repo.loadArea('1,2,3,4');
    repo.startLive('1,2,3,4');
    final loadsBefore = api.bboxes.length;

    // While the socket was down cell "b" changed owner on the server.
    api.cells = [
      mine,
      const Cell(id: 'b', lat: 50.001, lng: 8.7, owner: UserRef(id: 'u3', name: 'cy')),
    ];
    live.latest.addError(const LiveClosedException(1006));
    await settle(80);

    expect(live.sockets.length, 2);
    expect(api.bboxes.length, loadsBefore + 1);
    expect(api.bboxes.last, '1,2,3,4');
    expect(repo.snapshot.firstWhere((c) => c.id == 'b').owner!.name, 'cy');
  });

  test('the first connection does not refetch the area', () async {
    await repo.loadArea('1,2,3,4');
    final before = api.bboxes.length;
    repo.startLive('1,2,3,4');
    await settle(40);
    expect(api.bboxes.length, before);
  });

  test('an auth failure (4401) is not retried', () async {
    repo.startLive('1,2,3,4');
    live.latest.addError(const LiveClosedException(4401));
    await settle(80);
    expect(live.sockets.length, 1);
    expect(repo.liveWanted, isFalse);
  });

  test('stopLive stops reconnecting', () async {
    repo.startLive('1,2,3,4');
    repo.stopLive();
    await settle(50);
    expect(live.sockets.length, 1);
    expect(repo.liveWanted, isFalse);
  });

  test('no token means no socket', () async {
    token = null;
    repo.startLive('1,2,3,4');
    expect(live.sockets, isEmpty);
  });

  test('reportCell sends kind cell; leaderboard passes through', () async {
    await repo.reportCell('8a1', 'fake owner');
    expect(api.reports.single, {'kind': 'cell', 'target_id': '8a1', 'reason': 'fake owner'});
    expect((await repo.weeklyLeaderboard()).week, '2026-W45');
  });
}
