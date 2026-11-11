import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:looprun/data/repositories/run_repository.dart';
import 'package:looprun/data/services/foreground_service.dart';
import 'package:looprun/data/upload/upload_queue.dart';
import 'package:looprun/domain/recorder/run_recorder.dart';

import '../fakes/fakes.dart';

void main() {
  late MemoryStore store;
  late FakeApiService api;
  late FakeLocationService location;
  late FakePermissionService permissions;
  late FakeForegroundService foreground;
  late RunRepository repo;
  var now = 1000000;
  var ids = 0;

  GeoFix fix(double lat, double lng, {int? t, double acc = 5}) =>
      GeoFix(lat: lat, lng: lng, t: t ?? now, acc: acc);

  setUp(() {
    now = 1000000;
    ids = 0;
    store = MemoryStore();
    api = FakeApiService();
    location = FakeLocationService();
    permissions = FakePermissionService();
    foreground = FakeForegroundService();
    repo = RunRepository(
      store: store,
      location: location,
      permissions: permissions,
      foreground: foreground,
      uploads: UploadQueue(store: store, api: api, nowMs: () => now),
      api: api,
      nowMs: () => now,
      newId: () => 'run-${++ids}',
      tickInterval: const Duration(milliseconds: 20),
    );
  });

  tearDown(() async {
    await repo.dispose();
  });

  test('start creates the run, starts the service and publishes a recording snapshot', () async {
    await repo.start();
    expect(repo.current.status, RecorderStatus.recording);
    expect(repo.current.runId, 'run-1');
    expect(foreground.starts, 1);
    expect(permissions.requests, 1);
    expect(repo.isRecording, isTrue);
    expect(store.runIds, ['run-1']);
    await repo.stop();
  });

  test('fixes are written to the store before they count, and stop queues and uploads the run', () async {
    await repo.start();
    location.emit(fix(50.0, 8.7, t: 1));
    location.emit(fix(50.001, 8.7, t: 2));
    await settle();

    expect((await store.fixesFor('run-1')).length, 2);
    expect(repo.current.path.length, 2);
    expect(repo.current.distanceM, greaterThan(100));

    await repo.stop();
    expect(repo.current.status, RecorderStatus.finished);
    expect(repo.current.finishedRunId, 'run-1');
    expect(foreground.stops, greaterThan(0));
    expect(repo.isRecording, isFalse);

    await settle();
    expect(api.uploadedIds, ['run-1']);
    expect(store.jobs['run-1']!.stage, UploadStage.done);

    repo.acknowledge();
    expect(repo.current.status, RecorderStatus.idle);
    expect(repo.current.finishedRunId, isNull);
  });

  test('recorder and UI do not move until the database write has finished', () async {
    await repo.start();
    store.holdFixWrites = Completer<void>();
    location.emit(fix(50.0, 8.7, t: 1));
    location.emit(fix(50.001, 8.7, t: 2));
    await settle();

    // The disk has not answered yet: nothing may be counted or drawn.
    expect(repo.current.path, isEmpty);
    expect(repo.current.distanceM, 0);
    expect(await store.fixesFor('run-1'), isEmpty);

    store.holdFixWrites!.complete();
    await settle();
    expect(repo.current.path.length, 2);
    expect(repo.current.distanceM, greaterThan(100));
    expect((await store.fixesFor('run-1')).length, 2);
    await repo.stop();
  });

  test('stop waits for writes that are still in flight, so the last points are kept', () async {
    await repo.start();
    store.holdFixWrites = Completer<void>();
    location.emit(fix(50.0, 8.7, t: 1));
    location.emit(fix(50.001, 8.7, t: 2));
    await settle();

    var stopped = false;
    final stopping = repo.stop().then((_) => stopped = true);
    await settle(40);
    expect(stopped, isFalse, reason: 'stop must wait for the two pending writes');
    expect(repo.current.status, RecorderStatus.stopping);

    store.holdFixWrites!.complete();
    await stopping;
    expect(repo.current.status, RecorderStatus.finished);
    expect(repo.current.error, isNull);
    expect((await store.fixesFor('run-1')).length, 2);
    expect((await store.runById('run-1'))!.state, 'finished');
  });

  test('stop does not hang on a write that never finishes', () async {
    repo = RunRepository(
      store: store,
      location: location,
      permissions: permissions,
      foreground: foreground,
      uploads: UploadQueue(store: store, api: api, nowMs: () => now),
      api: api,
      nowMs: () => now,
      newId: () => 'run-${++ids}',
      tickInterval: const Duration(milliseconds: 20),
      pendingWriteTimeout: const Duration(milliseconds: 100),
    );
    await repo.start();
    store.holdFixWrites = Completer<void>(); // never completed
    location.emit(fix(50.0, 8.7, t: 1));
    await settle();

    await repo.stop().timeout(const Duration(seconds: 3));
    expect(repo.current.status, isNot(RecorderStatus.stopping));
    expect(repo.isRecording, isFalse);
  });

  test('a GPS stream that ends is reported while recording', () async {
    final own = FakeLocationService();
    repo = RunRepository(
      store: store,
      location: own,
      permissions: permissions,
      foreground: foreground,
      uploads: UploadQueue(store: store, api: api, nowMs: () => now),
      api: api,
      nowMs: () => now,
      newId: () => 'run-${++ids}',
      tickInterval: const Duration(milliseconds: 20),
    );
    await repo.start();
    await own.controller.close();
    await settle();
    expect(repo.current.error, contains('GPS stopped'));
    expect(repo.current.status, RecorderStatus.recording);
    await repo.stop();
  });

  test('a GPS stream error is shown and recording continues', () async {
    await repo.start();
    location.controller.addError(StateError('provider disabled'));
    await settle();
    expect(repo.current.error, contains('GPS error'));
    expect(repo.current.status, RecorderStatus.recording);
    await repo.stop();
  });

  test('a fix whose write fails does not count', () async {
    await repo.start();
    store.failFixWrites = true;
    location.emit(fix(50.0, 8.7));
    await settle();
    expect(repo.current.path, isEmpty);
    expect(repo.current.error, contains('Could not save a GPS point'));
    await repo.stop();
  });

  test('a run with fewer than two stored fixes is discarded', () async {
    await repo.start();
    location.emit(fix(50.0, 8.7));
    await settle();
    await repo.stop();
    expect(repo.current.finishedRunId, isNull);
    expect(repo.current.error, contains('too short'));
    expect(store.runIds, isEmpty);
    expect(api.uploadedIds, isEmpty);
  });

  test('pause and resume are stored and paused fixes are ignored', () async {
    await repo.start();
    await repo.pause();
    expect(repo.current.status, RecorderStatus.paused);
    expect((await store.runById('run-1'))!.state, 'paused');
    location.emit(fix(50.0, 8.7));
    await settle();
    expect((await store.fixesFor('run-1')), isEmpty);
    await repo.resume();
    expect(repo.current.status, RecorderStatus.recording);
    expect((await store.runById('run-1'))!.state, 'recording');
    await repo.stop();
  });

  test('without location permission nothing is created', () async {
    permissions.granted = false;
    await repo.start();
    expect(repo.current.status, RecorderStatus.idle);
    expect(repo.current.error, contains('permission'));
    expect(store.runIds, isEmpty);
    expect(foreground.starts, 0);
    expect(repo.isRecording, isFalse);
  });

  test('with location switched off nothing is created', () async {
    location.enabled = false;
    await repo.start();
    expect(repo.current.error, contains('turned off'));
    expect(store.runIds, isEmpty);
  });

  test('if the foreground service cannot start, the run row is discarded', () async {
    foreground.failStart = true;
    await repo.start();
    expect(repo.current.status, RecorderStatus.idle);
    expect(repo.current.error, contains('Could not start the run'));
    expect(store.runIds, isEmpty);
    expect(repo.isRecording, isFalse);
  });

  test('the Stop button in the notification stops and saves the run', () async {
    await repo.start();
    location.emit(fix(50.0, 8.7, t: 1));
    location.emit(fix(50.001, 8.7, t: 2));
    await settle();
    foreground.controller.add(ForegroundAction.stop);
    await settle(40);
    expect(repo.current.status, RecorderStatus.finished);
    expect(repo.current.finishedRunId, 'run-1');
    expect((await store.runById('run-1'))!.state, 'finished');
  });

  test('recovery finds an interrupted run and finishes or discards it', () async {
    await store.createRun('old', 5);
    await store.addFix('old', fix(50.0, 8.7, t: 10));
    await store.addFix('old', fix(50.001, 8.7, t: 20));
    final found = await repo.findUnfinishedRun();
    expect(found!.id, 'old');

    expect(await repo.finishRecoveredRun('old'), isTrue);
    expect((await store.runById('old'))!.endedAt, 20);
    await settle();
    expect(api.uploadedIds, ['old']);

    await store.createRun('tiny', 6);
    await store.addFix('tiny', fix(50.0, 8.7, t: 30));
    expect(await repo.finishRecoveredRun('tiny'), isFalse);
    expect(await store.runById('tiny'), isNull);
  });

  test('recovery ignores the run this process is recording', () async {
    await repo.start();
    expect(await repo.findUnfinishedRun(), isNull);
    await repo.stop();
  });

  test('reportRun sends kind run', () async {
    await repo.reportRun('abc', 'looks wrong');
    expect(api.reports, [
      {'kind': 'run', 'target_id': 'abc', 'reason': 'looks wrong'},
    ]);
  });

  test('retryUpload requeues a failed job and uploads it', () async {
    await store.createRun('r', 1);
    await store.markFinished('r', 2);
    await store.saveJob(const UploadJob(runId: 'r', stage: UploadStage.failed, lastError: 'boom'));
    await repo.retryUpload('r');
    expect(api.uploadedIds, ['r']);
    expect(store.jobs['r']!.stage, UploadStage.done);
  });
}
