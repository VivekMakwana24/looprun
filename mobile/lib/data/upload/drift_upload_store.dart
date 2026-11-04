import 'dart:convert';

import '../models/models.dart';
import '../db/app_database.dart';
import 'upload_queue.dart';

class DriftUploadStore implements UploadStore {
  DriftUploadStore(this.db);
  final AppDatabase db;

  UploadJob _toJob(RunRow r) {
    RunStatus? result;
    final raw = r.resultJson;
    if (raw != null) {
      try {
        result = RunStatus.fromJson((jsonDecode(raw) as Map).cast<String, dynamic>());
      } catch (_) {
        result = null;
      }
    }
    final stage = UploadStage.values.firstWhere(
      (s) => s.name == r.upload,
      orElse: () => UploadStage.queued,
    );
    return UploadJob(
      runId: r.id,
      stage: stage,
      attempts: r.attempts,
      nextAttemptAt: r.nextAttemptAt,
      lastError: r.lastError,
      result: result,
    );
  }

  @override
  Future<List<UploadJob>> activeJobs() async {
    final rows = await db.activeUploads();
    return rows.map(_toJob).toList();
  }

  @override
  Future<UploadJob?> getJob(String runId) async {
    final r = await db.runById(runId);
    return r == null ? null : _toJob(r);
  }

  @override
  Future<void> saveJob(UploadJob job) {
    return db.writeUpload(
      job.runId,
      upload: job.stage.name,
      attempts: job.attempts,
      nextAttemptAt: job.nextAttemptAt,
      lastError: job.lastError,
      resultJson: job.result == null ? null : jsonEncode(job.result!.toJson()),
    );
  }

  @override
  Future<RunUpload> buildPayload(String runId) async {
    final run = await db.runById(runId);
    if (run == null) {
      throw StateError('Run $runId not found');
    }
    final rows = await db.fixesFor(runId);
    final fixes = rows
        .map((f) => Fix(lat: f.lat, lng: f.lng, t: f.t, acc: f.acc, mock: f.isMock))
        .toList();
    final endedAt = run.endedAt ?? (fixes.isNotEmpty ? fixes.last.t : run.startedAt);
    return RunUpload(id: run.id, startedAt: run.startedAt, endedAt: endedAt, fixes: fixes);
  }
}
