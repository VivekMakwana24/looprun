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

const String gpsStoppedMessage = 'GPS stopped sending updates. Looprun is restarting it.';
const String gpsGaveUpMessage =
    'GPS stopped sending updates. Check that location is switched on, or finish the run.';
const String gpsErrorMessage = 'GPS problem. Check that location is switched on.';
const String saveFailedMessage =
    'Your run could not be saved as finished. All its GPS points are safe on this phone. '
    'Try again, or go back: Looprun offers to finish it the next time it starts.';
const String pausedNotificationText = 'Paused. Open Looprun to resume or finish.';
const String notificationsOffNotice =
    'Notifications are off for Looprun, so the recording notification and its Stop button are hidden. '
    'Your run is still recorded.';

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
    Duration gpsRestartDelay = const Duration(seconds: 2),
    this.maxGpsRestarts = 5,
  })  : _pendingWriteTimeout = pendingWriteTimeout,
        _gpsRestartDelay = gpsRestartDelay,
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

  /// The platform GPS stream should run until we cancel it. When it ends or fails on its own (location
  /// switched off, provider restarted) it is opened again after this delay, at most [maxGpsRestarts]
  /// times in a row; a fix that arrives resets the count.
  final Duration _gpsRestartDelay;
  final int maxGpsRestarts;
  int _gpsRestarts = 0;
  Timer? _gpsRestartTimer;

  /// The crash-recovery check that is still running, if any. start() waits for it, so the check can
  /// never stop the service of a run that began a moment later (review F5).
  Future<void>? _recoveryCheck;

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
      final recovery = _recoveryCheck;
      if (recovery != null) await recovery;
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
      // The notification (and its Stop button) only shows when notifications are allowed (review F4).
      var notificationsOn = true;
      try {
        notificationsOn = await _permissions.notificationsAllowed();
      } catch (_) {}
      _emit(RecordingSnapshot(
        status: RecorderStatus.recording,
        runId: runId,
        health: GpsHealth.searching,
        notice: notificationsOn ? null : notificationsOffNotice,
      ));
      _gpsRestarts = 0;
      _listenForFixes();
      _timer = Timer.periodic(_tickInterval, (_) => _tick());
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
      _emit(const RecordingSnapshot(error: 'Could not start the run. Please try again.'));
    } finally {
      _starting = false;
    }
  }

  void _listenForFixes() {
    _fixSub = _location.fixes().listen(_onFix, onError: _onFixError, onDone: _onFixesEnded);
  }

  Future<void> _onFix(GeoFix fix) async {
    final now = _nowMs();
    _health.onFix(now);
    _gpsRestarts = 0;
    if (_recorder.status != RecorderStatus.recording) return;
    final runId = _recorder.runId!;
    // 1. Write to the database first, before memory or UI change.
    final write = _store.addFix(runId, fix);
    final tracked = write.then<void>((_) {}, onError: (Object _) {});
    _pending.add(tracked);
    try {
      await write;
    } catch (e) {
      _emit(_snap.copyWith(error: 'Could not save a GPS point. Check the free space on your phone.'));
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
      accuracyM: fix.acc,
      clearError: _snap.error == gpsStoppedMessage || _snap.error == gpsErrorMessage,
    ));
  }

  /// The platform GPS stream ended on its own (it should run until we cancel it): open it again.
  void _onFixesEnded() {
    _fixSub = null;
    if (!_recorder.isActive) return;
    if (_gpsRestarts >= maxGpsRestarts) {
      _emit(_snap.copyWith(error: gpsGaveUpMessage));
      return;
    }
    _gpsRestarts++;
    _emit(_snap.copyWith(error: gpsStoppedMessage));
    _gpsRestartTimer?.cancel();
    _gpsRestartTimer = Timer(_gpsRestartDelay, () {
      _gpsRestartTimer = null;
      if (!_recorder.isActive || _fixSub != null) return;
      try {
        _listenForFixes();
      } catch (_) {
        _onFixesEnded();
      }
    });
  }

  /// An error event from the GPS stream. The stream may go on or end; if it ends, [_onFixesEnded] restarts it.
  void _onFixError(Object error) {
    if (!_recorder.isActive) return;
    _emit(_snap.copyWith(error: gpsErrorMessage));
  }

  void _tick() {
    if (!_snap.isActive) return;
    final health = _health.evaluate(_nowMs());
    _emit(_snap.copyWith(elapsedMs: _recorder.elapsedMs, health: health));
    if (_recorder.status == RecorderStatus.paused) return; // the notification says "Paused"
    if (health != _notified) {
      _notified = health;
      unawaited(_foreground.updateText(notificationTextFor(health)).catchError((Object _) {}));
    }
  }

  Future<void> pause() async {
    if (_recorder.status != RecorderStatus.recording) return;
    _recorder.pause();
    _emit(_snap.copyWith(status: RecorderStatus.paused, elapsedMs: _recorder.elapsedMs));
    // The notification must not say "Recording" while paused (review F3). GPS stays on so resume is instant.
    _notified = GpsHealth.inactive;
    unawaited(_foreground.updateText(pausedNotificationText).catchError((Object _) {}));
    final runId = _recorder.runId;
    if (runId != null) await _store.setRunState(runId, 'paused');
  }

  Future<void> resume() async {
    if (_recorder.status != RecorderStatus.paused) return;
    _recorder.resume();
    _emit(_snap.copyWith(status: RecorderStatus.recording));
    final health = _health.evaluate(_nowMs());
    _notified = health;
    unawaited(_foreground.updateText(notificationTextFor(health)).catchError((Object _) {}));
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
    try {
      await _teardown();
      // Wait for fixes whose write is still running, so the last point is not lost.
      // Bounded: a hung disk write must not leave the screen on "Saving..." forever.
      await Future.wait(List<Future<void>>.of(_pending)).timeout(
        _pendingWriteTimeout,
        onTimeout: () => <void>[],
      );
    } catch (_) {
      // Whatever went wrong while shutting down, the run must still leave "stopping" (review F8).
    }
    final endedAt = _recorder.endedAt ?? _nowMs();
    final elapsed = _recorder.elapsedMs;
    _recorder.finish();
    await _save(runId, endedAt, elapsed);
  }

  /// The finish that failed (disk full, database error), kept for [retrySave].
  ({String runId, int endedAt, int elapsedMs})? _unsaved;

  Future<void> _save(String runId, int endedAt, int elapsed) async {
    try {
      final stored = (await _store.fixesFor(runId)).length;
      if (stored < 2) {
        await _store.discardRun(runId);
        _unsaved = null;
        _recorder.reset();
        _emit(const RecordingSnapshot(
          error: 'That run was too short to save (no GPS points recorded).',
        ));
        return;
      }
      await _store.markFinished(runId, endedAt);
    } catch (_) {
      // The GPS points are in the database already; only marking the run finished failed. The row stays
      // "recording", so crash recovery also offers it on the next start.
      _unsaved = (runId: runId, endedAt: endedAt, elapsedMs: elapsed);
      _emit(RecordingSnapshot(
        status: RecorderStatus.finished,
        runId: runId,
        elapsedMs: elapsed,
        distanceM: _snap.distanceM,
        path: _snap.path,
        saveFailed: true,
        error: saveFailedMessage,
      ));
      return;
    }
    _unsaved = null;
    _emit(_snap.copyWith(
      status: RecorderStatus.finished,
      health: GpsHealth.inactive,
      finishedRunId: runId,
      elapsedMs: elapsed,
      saveFailed: false,
      clearError: true,
    ));
    unawaited(tickUploads());
  }

  /// "Try again" after a failed save (review blocker B2).
  Future<void> retrySave() async {
    final u = _unsaved;
    if (u == null || !_snap.saveFailed) return;
    _emit(_snap.copyWith(saveFailed: false, status: RecorderStatus.stopping, clearError: true));
    await _save(u.runId, u.endedAt, u.elapsedMs);
  }

  /// The screen has shown the result of the finished run; go back to idle.
  /// Also "Back to the map" after a failed save: the run stays on this phone for crash recovery.
  void acknowledge() {
    _unsaved = null;
    if (_recorder.status == RecorderStatus.finished) _recorder.reset();
    _path.clear();
    _emit(const RecordingSnapshot());
  }

  void clearError() {
    _emit(_snap.copyWith(clearError: true));
  }

  Future<void> _teardown() async {
    // Each step is guarded: a failing cancel must not stop the run from being saved. The cancel futures
    // are not awaited: nothing is left to do after them, and a cancel future that never completes (some
    // stream sources) must not leave the run in "stopping".
    final fixSub = _fixSub;
    _fixSub = null;
    final actionSub = _actionSub;
    _actionSub = null;
    for (final sub in [fixSub, actionSub]) {
      if (sub == null) continue;
      try {
        unawaited(sub.cancel().then<void>((_) {}, onError: (Object _) {}));
      } catch (_) {}
    }
    _timer?.cancel();
    _timer = null;
    _gpsRestartTimer?.cancel();
    _gpsRestartTimer = null;
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
  Future<RunSummary?> findUnfinishedRun() {
    final check = _findUnfinishedRun();
    final done = check.then<void>((_) {}, onError: (Object _) {});
    _recoveryCheck = done;
    unawaited(done.whenComplete(() {
      if (identical(_recoveryCheck, done)) _recoveryCheck = null;
    }));
    return check;
  }

  Future<RunSummary?> _findUnfinishedRun() async {
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
