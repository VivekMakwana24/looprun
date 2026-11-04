import '../models/api_exception.dart';
import '../models/models.dart';
import 'backoff.dart';

enum UploadStage { queued, processing, done, failed }

class UploadJob {
  const UploadJob({
    required this.runId,
    required this.stage,
    this.attempts = 0,
    this.nextAttemptAt = 0,
    this.lastError,
    this.result,
  });

  final String runId;
  final UploadStage stage;

  /// Consecutive failures so far.
  final int attempts;

  /// Epoch ms; the job is not touched before this time.
  final int nextAttemptAt;
  final String? lastError;
  final RunStatus? result;

  UploadJob copyWith({
    UploadStage? stage,
    int? attempts,
    int? nextAttemptAt,
    String? lastError,
    bool clearError = false,
    RunStatus? result,
  }) {
    return UploadJob(
      runId: runId,
      stage: stage ?? this.stage,
      attempts: attempts ?? this.attempts,
      nextAttemptAt: nextAttemptAt ?? this.nextAttemptAt,
      lastError: clearError ? null : (lastError ?? this.lastError),
      result: result ?? this.result,
    );
  }
}

/// Persistence for upload jobs (Drift in the app, a map in tests).
abstract class UploadStore {
  /// Jobs in stage queued or processing.
  Future<List<UploadJob>> activeJobs();
  Future<UploadJob?> getJob(String runId);
  Future<void> saveJob(UploadJob job);
  Future<RunUpload> buildPayload(String runId);
}

abstract class RunsApi {
  Future<RunStatus> uploadRun(RunUpload run);
  Future<RunStatus> getRun(String id);
}

/// Uploads finished runs and polls their status. All progress is persisted through [UploadStore],
/// so the queue survives app restarts. Uploads are idempotent because the run id is client generated.
class UploadQueue {
  UploadQueue({
    required this.store,
    required this.api,
    this.policy = const BackoffPolicy(),
    this.pollInterval = const Duration(seconds: 3),
    int Function()? nowMs,
  }) : _nowMs = nowMs ?? (() => DateTime.now().millisecondsSinceEpoch);

  final UploadStore store;
  final RunsApi api;
  final BackoffPolicy policy;
  final Duration pollInterval;
  final int Function() _nowMs;
  bool _busy = false;
  bool _authBlocked = false;

  /// True after a 401: nothing is sent until [resumeAfterAuth]. Jobs stay queued, untouched.
  bool get isBlockedByAuth => _authBlocked;

  /// Call when a user signed in. Clears the block that a 401 set.
  void resumeAfterAuth() => _authBlocked = false;

  /// Processes every job that is due. Returns how many jobs were attempted.
  Future<int> tick() async {
    if (_busy || _authBlocked) return 0;
    _busy = true;
    var touched = 0;
    try {
      final now = _nowMs();
      final jobs = await store.activeJobs();
      for (final job in jobs) {
        if (_authBlocked) break;
        if (job.nextAttemptAt > now) continue;
        touched++;
        await _process(job, now);
      }
    } finally {
      _busy = false;
    }
    return touched;
  }

  /// Puts a failed job back in the queue (manual "try again").
  Future<void> requeue(String runId) async {
    final job = await store.getJob(runId);
    if (job == null) return;
    await store.saveJob(UploadJob(runId: runId, stage: UploadStage.queued, result: job.result));
  }

  Future<void> _process(UploadJob job, int now) async {
    try {
      final RunStatus status;
      if (job.stage == UploadStage.queued) {
        final payload = await store.buildPayload(job.runId);
        status = await api.uploadRun(payload);
      } else {
        status = await api.getRun(job.runId);
      }
      await _onStatus(job, status, now);
    } on ApiException catch (e) {
      await _onError(job, e, now);
    } catch (e) {
      // Unexpected (missing run row, malformed body): fail this job only, keep the others going.
      await store.saveJob(job.copyWith(stage: UploadStage.failed, lastError: 'Unexpected error: $e'));
    }
  }

  Future<void> _onStatus(UploadJob job, RunStatus status, int now) async {
    if (status.isProcessing) {
      await store.saveJob(UploadJob(
        runId: job.runId,
        stage: UploadStage.processing,
        attempts: 0,
        nextAttemptAt: now + pollInterval.inMilliseconds,
        result: status,
      ));
    } else {
      await store.saveJob(UploadJob(
        runId: job.runId,
        stage: UploadStage.done,
        attempts: 0,
        nextAttemptAt: 0,
        result: status,
      ));
    }
  }

  Future<void> _onError(UploadJob job, ApiException e, int now) async {
    if (e.statusCode == 401) {
      // The token is no good, not the run. Keep the job exactly as it is (no attempt counted, no
      // failure shown) and stop sending until somebody signs in again.
      _authBlocked = true;
      return;
    }
    final failures = job.attempts + 1;
    if (policy.shouldRetry(e.statusCode, failures)) {
      await store.saveJob(job.copyWith(
        attempts: failures,
        nextAttemptAt: now + policy.delayFor(failures).inMilliseconds,
        lastError: e.message,
      ));
    } else {
      await store.saveJob(job.copyWith(
        stage: UploadStage.failed,
        attempts: failures,
        lastError: e.message,
      ));
    }
  }
}
