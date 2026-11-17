import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:looprun/data/repositories/run_repository.dart';
import 'package:looprun/data/services/foreground_service.dart';
import 'package:looprun/data/services/location_service.dart';
import 'package:looprun/data/upload/upload_queue.dart';
import 'package:looprun/domain/recorder/run_recorder.dart';

import '../fakes/fakes.dart';

/// A GPS source whose stream can end (like the platform stream does when location is switched off)
/// and be opened again.
class RestartableLocationService implements LocationService {
  StreamController<GeoFix>? _current;
  int opened = 0;

  /// When true every stream ends as soon as it is listened to.
  bool endAtOnce = false;

  @override
  Future<bool> isEnabled() async => true;

  @override
  Future<GeoFix> currentPosition() async => const GeoFix(lat: 50, lng: 8.7, t: 1, acc: 5);

  @override
  Stream<GeoFix> fixes() {
    opened++;
    final c = StreamController<GeoFix>();
    _current = c;
    if (endAtOnce) unawaited(c.close());
    return c.stream;
  }

  void emit(GeoFix fix) => _current!.add(fix);

  Future<void> endStream() => _current!.close();
}

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
    expect(repo.current.error, gpsErrorMessage);
    expect(repo.current.error, isNot(contains('provider disabled')), reason: 'never the raw exception');
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

  test('a GPS stream that ends is opened again and recording goes on', () async {
    final own = RestartableLocationService();
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
      gpsRestartDelay: const Duration(milliseconds: 10),
    );
    await repo.start();
    expect(own.opened, 1);
    own.emit(fix(50.0, 8.7, t: 1));
    await settle();
    await own.endStream();
    await settle(40);
    expect(own.opened, 2, reason: 'the stream was opened a second time');
    expect(repo.current.error, gpsStoppedMessage);
    own.emit(fix(50.001, 8.7, t: 2));
    await settle();
    expect(repo.current.error, isNull, reason: 'the warning goes away when points arrive again');
    expect((await store.fixesFor('run-1')).length, 2);
    await repo.stop();
    expect(repo.current.status, RecorderStatus.finished);
  });

  test('a GPS stream that keeps ending is given up after maxGpsRestarts, the run stays alive', () async {
    final own = RestartableLocationService()..endAtOnce = true;
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
      gpsRestartDelay: const Duration(milliseconds: 2),
      maxGpsRestarts: 3,
    );
    await repo.start();
    await settle(80);
    expect(own.opened, 4, reason: 'the first stream plus three restarts');
    expect(repo.current.error, gpsGaveUpMessage);
    expect(repo.current.status, RecorderStatus.recording);
    await repo.stop();
  });

  test('the notification says Paused while paused and Recording again after resume (review F3)', () async {
    await repo.start();
    await repo.pause();
    await settle();
    expect(foreground.texts.last, pausedNotificationText);
    await repo.resume();
    await settle();
    expect(foreground.texts.last, isNot(pausedNotificationText));
    await repo.stop();
  });

  test('with notifications switched off the runner is told, and the run still records (review F4)', () async {
    permissions.notifications = false;
    await repo.start();
    expect(repo.current.status, RecorderStatus.recording);
    expect(repo.current.notice, notificationsOffNotice);
    await repo.stop();
  });

  test('the accuracy of the newest fix is published', () async {
    await repo.start();
    expect(repo.current.accuracyM, isNull);
    location.emit(fix(50.0, 8.7, t: 1, acc: 6));
    await settle();
    expect(repo.current.accuracyM, 6);
    await repo.stop();
  });

  test('a start that follows a recovery check waits for it (review F5)', () async {
    final check = repo.findUnfinishedRun();
    final started = repo.start();
    expect(await check, isNull);
    await started;
    expect(repo.current.status, RecorderStatus.recording);
    expect(foreground.stops, 0, reason: 'the recovery check must not stop the new run\'s service');
    await repo.stop();
  });

  test('a failed save is a clear error with retry, not an endless "saving" (review B2)', () async {
    await repo.start();
    location.emit(fix(50.0, 8.7, t: 1));
    location.emit(fix(50.001, 8.7, t: 2));
    await settle();
    store.failMarkFinished = 1;
    await repo.stop();
    expect(repo.current.saveFailed, isTrue);
    expect(repo.current.error, saveFailedMessage);
    expect(repo.current.finishedRunId, isNull);
    expect(repo.current.status, isNot(RecorderStatus.stopping));
    expect(repo.isRecording, isFalse);
    // The points are safe and the row is still there for recovery.
    expect((await store.fixesFor('run-1')).length, 2);
    expect((await store.runById('run-1'))!.state, 'recording');

    await repo.retrySave();
    expect(repo.current.saveFailed, isFalse);
    expect(repo.current.error, isNull);
    expect(repo.current.finishedRunId, 'run-1');
    expect((await store.runById('run-1'))!.state, 'finished');
  });

  test('going back after a failed save leaves the run for crash recovery', () async {
    await repo.start();
    location.emit(fix(50.0, 8.7, t: 1));
    location.emit(fix(50.001, 8.7, t: 2));
    await settle();
    store.failMarkFinished = 1;
    await repo.stop();
    repo.acknowledge();
    expect(repo.current.status, RecorderStatus.idle);
    expect((await repo.findUnfinishedRun())!.id, 'run-1');
  });
}
