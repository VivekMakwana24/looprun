import 'dart:async';

import 'package:uuid/uuid.dart';

import '../../domain/recorder/geo.dart';
import '../../domain/recorder/gps_health.dart';
import '../../domain/recorder/run_recorder.dart';
import '../db/run_store.dart';
import '../models/models.dart';
import '../models/recording_snapshot.dart';
import '../services/api_service.dart';
import '../services/foreground_service.dart';
import '../services/location_service.dart';
import '../services/permission_service.dart';
import '../upload/upload_queue.dart';

/// Source of truth for runs. The local database is authoritative; the network is only a sync target
/// (the upload queue). Owns the pure-Dart [RunRecorder] and feeds it fixes from [LocationService].
///
/// Write-first rule: every fix is stored before the recorder or the UI see it, so a killed app or a dead
/// network never loses a run.
class RunRepository {
  RunRepository({
    required RunStore store,
    required LocationService location,
    required PermissionService permissions,
    required ForegroundService foreground,
    required UploadQueue uploads,
    required ApiService api,
    int Function()? nowMs,
    String Function()? newId,
    Duration tickInterval = const Duration(seconds: 1),
    Duration pendingWriteTimeout = const Duration(seconds: 5),
  })  : _pendingWriteTimeout = pendingWriteTimeout,
        _store = store,
        _location = location,
        _permissions = permissions,
        _foreground = foreground,
        _uploads = uploads,
        _api = api,
        _nowMs = nowMs ?? (() => DateTime.now().millisecondsSinceEpoch),
        _tickInterval = tickInterval {
    _recorder = RunRecorder(nowMs: _nowMs, newId: newId ?? (() => const Uuid().v4()));
  }

  final RunStore _store;
  final LocationService _location;
  final PermissionService _permissions;
  final ForegroundService _foreground;
  final UploadQueue _uploads;
  final ApiService _api;
  final int Function() _nowMs;
  final Duration _tickInterval;

  /// How long stop() waits for fix writes that are still running before it carries on.
  final Duration _pendingWriteTimeout;

  late final RunRecorder _recorder;
  final GpsHealthMonitor _health = GpsHealthMonitor();
  final StreamController<RecordingSnapshot> _snapshots =
      StreamController<RecordingSnapshot>.broadcast();

  RecordingSnapshot _snap = const RecordingSnapshot();
  final List<PathPoint> _path = [];
  StreamSubscription<GeoFix>? _fixSub;
  StreamSubscription<ForegroundAction>? _actionSub;
  Timer? _timer;
  GpsHealth _notified = GpsHealth.inactive;
  bool _starting = false;

  /// Database writes of fixes that are still in flight (the run is only finished after they complete).
  final List<Future<void>> _pending = [];

  /// The latest snapshot; [snapshots] publishes changes.
  RecordingSnapshot get current => _snap;
  Stream<RecordingSnapshot> get snapshots => _snapshots.stream;

  /// True while this process is starting, recording, paused or stopping a run.
  bool get isRecording =>
      _starting || _recorder.isActive || _recorder.status == RecorderStatus.stopping;

  int? _lastStoppedAtMs;

  /// When the last run stopped (epoch ms), or null. Used to hold back a sign-out right after a run.
  int? get lastStoppedAtMs => _lastStoppedAtMs;

  void _emit(RecordingSnapshot s) {
    _snap = s;
    if (!_snapshots.isClosed) _snapshots.add(s);
  }

  // ------------------------------------------------------------------ recording

  /// Asks for permission, creates the run row, starts the foreground service and the GPS stream.
  /// Call only after the user tapped Start, and only after the disclosure was accepted.
  Future<void> start() async {
    if (isRecording) return;
    _starting = true;
    _emit(_snap.copyWith(clearError: true));
    String? createdRunId;
    try {
      final granted = await _permissions.requestLocation();
      if (!granted) {
        _emit(_snap.copyWith(
          error: 'Location permission is needed to record a run. You can allow it in system settings.',
        ));
        return;
      }
      if (!await _location.isEnabled()) {
        _emit(_snap.copyWith(error: 'Location is turned off. Turn it on and try again.'));
        return;
      }
      _recorder.reset();
      _recorder.start();
      final runId = _recorder.runId!;
      await _store.createRun(runId, _recorder.startedAt!);
      createdRunId = runId;
      await _foreground.start();
      _path.clear();
      _health.start(_nowMs());
      _notified = GpsHealth.searching;
      _actionSub = _foreground.actions.listen((action) {
        if (action == ForegroundAction.stop) unawaited(stop());
      });
      _fixSub = _location.fixes().listen(_onFix, onError: _onFixError, onDone: _onFixesEnded);
      _timer = Timer.periodic(_tickInterval, (_) => _tick());
      _emit(RecordingSnapshot(
        status: RecorderStatus.recording,
        runId: runId,
        health: GpsHealth.searching,
      ));
    } catch (e) {
      await _teardown();
      if (_recorder.isActive) _recorder.stop();
      if (_recorder.status == RecorderStatus.stopping) _recorder.finish();
      _recorder.reset();
      if (createdRunId != null) {
        // Do not leave an empty "unfinished" run behind for the next launch.
        try {
          await _store.discardRun(createdRunId);
        } catch (_) {}
      }
      _emit(RecordingSnapshot(error: 'Could not start the run: $e'));
    } finally {
      _starting = false;
    }
  }

  Future<void> _onFix(GeoFix fix) async {
    final now = _nowMs();
    _health.onFix(now);
    if (_recorder.status != RecorderStatus.recording) return;
    final runId = _recorder.runId!;
    // 1. Write to the database first, before memory or UI change.
    final write = _store.addFix(runId, fix);
    final tracked = write.then<void>((_) {}, onError: (Object _) {});
    _pending.add(tracked);
    try {
      await write;
    } catch (e) {
      _emit(_snap.copyWith(error: 'Could not save a GPS point: $e'));
      return; // do not count what was not stored
    } finally {
      _pending.remove(tracked);
    }
    // 2. Then the recorder and the UI.
    if (!_recorder.addFix(fix)) return;
    _path.add(PathPoint(fix.lat, fix.lng));
    _emit(_snap.copyWith(
      distanceM: _recorder.distanceM,
      health: _health.evaluate(now),
      path: List<PathPoint>.of(_path),
    ));
  }

  /// The platform GPS stream ended on its own (it should run until we cancel it).
  void _onFixesEnded() {
    if (_recorder.status != RecorderStatus.recording && _recorder.status != RecorderStatus.paused) return;
    _emit(_snap.copyWith(
      error: 'GPS stopped sending updates. Stop the run and start again if no points appear.',
    ));
  }

  void _onFixError(Object error) {
    _emit(_snap.copyWith(error: 'GPS error: $error'));
  }

  void _tick() {
    if (!_snap.isActive) return;
    final health = _health.evaluate(_nowMs());
    _emit(_snap.copyWith(elapsedMs: _recorder.elapsedMs, health: health));
    if (health != _notified) {
      _notified = health;
      unawaited(_foreground.updateText(notificationTextFor(health)).catchError((Object _) {}));
    }
  }

  Future<void> pause() async {
    if (_recorder.status != RecorderStatus.recording) return;
    _recorder.pause();
    _emit(_snap.copyWith(status: RecorderStatus.paused, elapsedMs: _recorder.elapsedMs));
    final runId = _recorder.runId;
    if (runId != null) await _store.setRunState(runId, 'paused');
  }

  Future<void> resume() async {
    if (_recorder.status != RecorderStatus.paused) return;
    _recorder.resume();
    _emit(_snap.copyWith(status: RecorderStatus.recording));
    final runId = _recorder.runId;
    if (runId != null) await _store.setRunState(runId, 'recording');
  }

  /// Stops recording, waits for the last database write, marks the run complete locally and queues it.
  /// Also called by the Stop button in the foreground notification.
  Future<void> stop() async {
    if (!_recorder.isActive) return;
    final runId = _recorder.runId!;
    _lastStoppedAtMs = _nowMs();
    _recorder.stop(); // stopping: no new fixes are accepted
    _emit(_snap.copyWith(status: RecorderStatus.stopping, elapsedMs: _recorder.elapsedMs));
    await _teardown();
    // Wait for fixes whose write is still running, so the last point is not lost.
    // Bounded: a hung disk write must not leave the screen on "Saving..." forever.
    await Future.wait(List<Future<void>>.of(_pending)).timeout(
      _pendingWriteTimeout,
      onTimeout: () => <void>[],
    );
    final endedAt = _recorder.endedAt ?? _nowMs();
    final elapsed = _recorder.elapsedMs;
    _recorder.finish();
    try {
      final stored = (await _store.fixesFor(runId)).length;
      if (stored < 2) {
        await _store.discardRun(runId);
        _recorder.reset();
        _emit(const RecordingSnapshot(
          error: 'That run was too short to save (no GPS points recorded).',
        ));
        return;
      }
      await _store.markFinished(runId, endedAt);
    } catch (e) {
      _emit(RecordingSnapshot(
        status: RecorderStatus.finished,
        error: 'Could not save the run: $e',
      ));
      return;
    }
    _emit(_snap.copyWith(
      status: RecorderStatus.finished,
      health: GpsHealth.inactive,
      finishedRunId: runId,
      elapsedMs: elapsed,
    ));
    unawaited(tickUploads());
  }

  /// The screen has shown the result of the finished run; go back to idle.
  void acknowledge() {
    if (_recorder.status == RecorderStatus.finished) _recorder.reset();
    _path.clear();
    _emit(const RecordingSnapshot());
  }

  void clearError() {
    _emit(_snap.copyWith(clearError: true));
  }

  Future<void> _teardown() async {
    // Each step is guarded: a failing cancel must not stop the run from being saved.
    try {
      await _fixSub?.cancel();
    } catch (_) {}
    _fixSub = null;
    try {
      await _actionSub?.cancel();
    } catch (_) {}
    _actionSub = null;
    _timer?.cancel();
    _timer = null;
    _health.stop();
    _notified = GpsHealth.inactive;
    try {
      await _foreground.stop();
    } catch (_) {
      // Stopping a service that is not running is fine.
    }
  }

  // ------------------------------------------------------------------ crash recovery

  /// A run that was still recording when the app died, or null. A leftover foreground service from the
  /// previous process is stopped first. Never reports the run this process is recording right now.
  Future<RunSummary?> findUnfinishedRun() async {
    if (isRecording) return null;
    try {
      await _foreground.stopIfRunning();
    } catch (_) {}
    final run = await _store.unfinishedRun();
    if (run == null || isRecording) return null;
    return run;
  }

  /// Marks an interrupted run complete and queues it. Returns false (and deletes it) when it has fewer
  /// than two fixes.
  Future<bool> finishRecoveredRun(String runId) async {
    final fixes = await _store.fixesFor(runId);
    if (fixes.length < 2) {
      await _store.discardRun(runId);
      return false;
    }
    await _store.markFinished(runId, fixes.last.t);
    unawaited(tickUploads());
    return true;
  }

  Future<void> discardRun(String runId) => _store.discardRun(runId);

  // ------------------------------------------------------------------ reading and uploading

  Stream<RunSummary?> watchRun(String id) => _store.watchRun(id);
  Stream<List<RunSummary>> watchRecentRuns({int limit = 10}) => _store.watchRecentRuns(limit: limit);

  /// Processes due uploads; never throws.
  Future<void> tickUploads() async {
    try {
      await _uploads.tick();
    } catch (_) {}
  }

  /// Manual "try again" for a failed upload.
  Future<void> retryUpload(String runId) async {
    await _uploads.requeue(runId);
    await tickUploads();
  }

  /// Report a run to the moderators (rate limited to 20 per hour by the server).
  Future<void> reportRun(String runId, String reason) {
    return _api.report(kind: 'run', targetId: runId, reason: reason);
  }

  Future<void> dispose() async {
    await _teardown();
    await _snapshots.close();
  }
}
