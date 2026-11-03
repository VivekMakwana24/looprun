import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:uuid/uuid.dart';

import '../../core/providers.dart';
import '../../recorder/gps_health.dart';
import '../../recorder/run_recorder.dart';

class PathPoint {
  const PathPoint(this.lat, this.lng);
  final double lat;
  final double lng;
}

class RunUiState {
  const RunUiState({
    this.status = RecorderStatus.idle,
    this.runId,
    this.elapsedMs = 0,
    this.distanceM = 0,
    this.health = GpsHealth.inactive,
    this.path = const [],
    this.error,
    this.finishedRunId,
  });

  final RecorderStatus status;
  final String? runId;
  final int elapsedMs;
  final double distanceM;
  final GpsHealth health;
  final List<PathPoint> path;
  final String? error;

  /// Set once when a run was finished and saved; the screen opens the result and then calls acknowledge().
  final String? finishedRunId;

  bool get isActive => status == RecorderStatus.recording || status == RecorderStatus.paused;

  RunUiState copyWith({
    RecorderStatus? status,
    String? runId,
    int? elapsedMs,
    double? distanceM,
    GpsHealth? health,
    List<PathPoint>? path,
    String? error,
    bool clearError = false,
    String? finishedRunId,
  }) {
    return RunUiState(
      status: status ?? this.status,
      runId: runId ?? this.runId,
      elapsedMs: elapsedMs ?? this.elapsedMs,
      distanceM: distanceM ?? this.distanceM,
      health: health ?? this.health,
      path: path ?? this.path,
      error: clearError ? null : (error ?? this.error),
      finishedRunId: finishedRunId ?? this.finishedRunId,
    );
  }
}

int _now() => DateTime.now().millisecondsSinceEpoch;

class RunController extends Notifier<RunUiState> {
  late RunRecorder _recorder;
  final GpsHealthMonitor _health = GpsHealthMonitor();
  StreamSubscription<Position>? _sub;
  Timer? _timer;
  GpsHealth _notified = GpsHealth.inactive;

  @override
  RunUiState build() {
    _recorder = RunRecorder(nowMs: _now, newId: () => const Uuid().v4());
    ref.onDispose(() {
      _sub?.cancel();
      _timer?.cancel();
    });
    return const RunUiState();
  }

  /// Called only from the visible Run screen when the user taps Start.
  Future<void> start() async {
    if (state.isActive) return;
    state = state.copyWith(clearError: true);
    try {
      final granted = await ref.read(permissionGatewayProvider).requestLocation();
      if (!granted) {
        state = state.copyWith(
          error: 'Location permission is needed to record a run. You can allow it in system settings.',
        );
        return;
      }
      if (!await Geolocator.isLocationServiceEnabled()) {
        state = state.copyWith(error: 'Location is turned off. Turn it on and try again.');
        return;
      }
      _recorder.reset();
      _recorder.start();
      final runId = _recorder.runId!;
      await ref.read(databaseProvider).createRun(runId, _recorder.startedAt!);
      await ref.read(runServiceProvider).start();
      _health.start(_now());
      _notified = GpsHealth.searching;
      _sub = Geolocator.getPositionStream(
        locationSettings: AndroidSettings(
          accuracy: LocationAccuracy.best,
          distanceFilter: 0,
          intervalDuration: const Duration(seconds: 1),
        ),
      ).listen(_onPosition, onError: _onStreamError);
      _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
      state = RunUiState(
        status: RecorderStatus.recording,
        runId: runId,
        health: GpsHealth.searching,
      );
    } catch (e) {
      await _teardown();
      if (_recorder.isActive) _recorder.finish();
      _recorder.reset();
      state = RunUiState(error: 'Could not start the run: $e');
    }
  }

  Future<void> _onPosition(Position p) async {
    final now = _now();
    _health.onFix(now);
    final fix = GeoFix(
      lat: p.latitude,
      lng: p.longitude,
      t: p.timestamp.millisecondsSinceEpoch,
      acc: p.accuracy,
      isMock: p.isMocked,
    );
    if (!_recorder.addFix(fix)) return;
    final runId = _recorder.runId!;
    final path = List<PathPoint>.of(state.path)..add(PathPoint(fix.lat, fix.lng));
    state = state.copyWith(
      distanceM: _recorder.distanceM,
      health: _health.evaluate(now),
      path: path,
    );
    try {
      await ref.read(databaseProvider).addFix(
            runId: runId,
            lat: fix.lat,
            lng: fix.lng,
            t: fix.t,
            acc: fix.acc,
            isMock: fix.isMock,
          );
    } catch (e) {
      state = state.copyWith(error: 'Could not save a GPS point: $e');
    }
  }

  void _onStreamError(Object error) {
    state = state.copyWith(error: 'GPS error: $error');
  }

  void _tick() {
    if (!state.isActive) return;
    final now = _now();
    final health = _health.evaluate(now);
    state = state.copyWith(elapsedMs: _recorder.elapsedMs, health: health);
    if (health != _notified) {
      _notified = health;
      ref.read(runServiceProvider).updateText(notificationTextFor(health));
    }
  }

  void pause() {
    if (state.status != RecorderStatus.recording) return;
    _recorder.pause();
    final runId = _recorder.runId;
    if (runId != null) {
      ref.read(databaseProvider).setRunState(runId, 'paused');
    }
    state = state.copyWith(status: RecorderStatus.paused, elapsedMs: _recorder.elapsedMs);
  }

  void resume() {
    if (state.status != RecorderStatus.paused) return;
    _recorder.resume();
    final runId = _recorder.runId;
    if (runId != null) {
      ref.read(databaseProvider).setRunState(runId, 'recording');
    }
    state = state.copyWith(status: RecorderStatus.recording);
  }

  /// Stops recording, marks the run complete locally and queues it for upload.
  Future<void> stop() async {
    if (!state.isActive) return;
    final db = ref.read(databaseProvider);
    final runId = _recorder.runId!;
    await _teardown();
    _recorder.finish();
    final fixCount = _recorder.fixCount;
    final endedAt = _recorder.endedAt ?? _now();
    if (fixCount < 2) {
      await db.discardRun(runId);
      _recorder.reset();
      state = const RunUiState(error: 'That run was too short to save (no GPS points recorded).');
      return;
    }
    await db.markFinished(runId, endedAt);
    state = state.copyWith(
      status: RecorderStatus.finished,
      health: GpsHealth.inactive,
      finishedRunId: runId,
      elapsedMs: _recorder.elapsedMs,
    );
    unawaited(ref.read(uploadQueueProvider).tick());
  }

  /// Called by the screen after it has opened the result screen.
  void acknowledge() {
    if (_recorder.status == RecorderStatus.finished) _recorder.reset();
    state = const RunUiState();
  }

  void clearError() {
    state = state.copyWith(clearError: true);
  }

  Future<void> _teardown() async {
    await _sub?.cancel();
    _sub = null;
    _timer?.cancel();
    _timer = null;
    _health.stop();
    _notified = GpsHealth.inactive;
    try {
      await ref.read(runServiceProvider).stop();
    } catch (_) {
      // Stopping a service that is not running is fine.
    }
  }
}

final runControllerProvider = NotifierProvider<RunController, RunUiState>(RunController.new);
