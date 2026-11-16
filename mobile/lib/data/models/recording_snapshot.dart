import '../../domain/recorder/geo.dart';
import '../../domain/recorder/gps_health.dart';
import '../../domain/recorder/run_recorder.dart';

/// Immutable picture of the run being recorded, published by `RunRepository`.
class RecordingSnapshot {
  const RecordingSnapshot({
    this.status = RecorderStatus.idle,
    this.runId,
    this.elapsedMs = 0,
    this.distanceM = 0,
    this.health = GpsHealth.inactive,
    this.path = const [],
    this.accuracyM,
    this.error,
    this.notice,
    this.finishedRunId,
  });

  final RecorderStatus status;
  final String? runId;
  final int elapsedMs;
  final double distanceM;
  final GpsHealth health;
  final List<PathPoint> path;

  /// Horizontal accuracy of the latest fix in metres, or null before the first fix.
  final double? accuracyM;
  final String? error;

  /// Something the runner should know that is not a failure (for example: notifications are off).
  final String? notice;

  /// Set when a run was finished and saved, until the screen calls `acknowledge()`.
  final String? finishedRunId;

  bool get isActive => status == RecorderStatus.recording || status == RecorderStatus.paused;

  RecordingSnapshot copyWith({
    RecorderStatus? status,
    String? runId,
    int? elapsedMs,
    double? distanceM,
    GpsHealth? health,
    List<PathPoint>? path,
    double? accuracyM,
    String? error,
    String? notice,
    bool clearError = false,
    String? finishedRunId,
  }) {
    return RecordingSnapshot(
      status: status ?? this.status,
      runId: runId ?? this.runId,
      elapsedMs: elapsedMs ?? this.elapsedMs,
      distanceM: distanceM ?? this.distanceM,
      health: health ?? this.health,
      path: path ?? this.path,
      accuracyM: accuracyM ?? this.accuracyM,
      error: clearError ? null : (error ?? this.error),
      notice: notice ?? this.notice,
      finishedRunId: finishedRunId ?? this.finishedRunId,
    );
  }
}
