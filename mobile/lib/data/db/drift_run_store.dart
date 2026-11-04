import 'dart:convert';

import '../../domain/recorder/run_recorder.dart';
import '../models/models.dart';
import 'app_database.dart';
import 'run_store.dart';

class DriftRunStore implements RunStore {
  DriftRunStore(this.db);
  final AppDatabase db;

  RunSummary _toSummary(RunRow r) {
    RunStatus? result;
    final raw = r.resultJson;
    if (raw != null) {
      try {
        result = RunStatus.fromJson((jsonDecode(raw) as Map).cast<String, dynamic>());
      } catch (_) {
        result = null;
      }
    }
    return RunSummary(
      id: r.id,
      startedAt: r.startedAt,
      endedAt: r.endedAt,
      state: r.state,
      upload: r.upload,
      attempts: r.attempts,
      lastError: r.lastError,
      result: result,
    );
  }

  @override
  Future<void> createRun(String id, int startedAt) => db.createRun(id, startedAt);

  @override
  Future<void> addFix(String runId, GeoFix fix) {
    return db.addFix(
      runId: runId,
      lat: fix.lat,
      lng: fix.lng,
      t: fix.t,
      acc: fix.acc,
      isMock: fix.isMock,
    );
  }

  @override
  Future<List<Fix>> fixesFor(String runId) async {
    final rows = await db.fixesFor(runId);
    return rows
        .map((f) => Fix(lat: f.lat, lng: f.lng, t: f.t, acc: f.acc, mock: f.isMock))
        .toList();
  }

  @override
  Future<RunSummary?> runById(String id) async {
    final r = await db.runById(id);
    return r == null ? null : _toSummary(r);
  }

  @override
  Future<RunSummary?> unfinishedRun() async {
    final r = await db.unfinishedRun();
    return r == null ? null : _toSummary(r);
  }

  @override
  Future<void> setRunState(String id, String state) => db.setRunState(id, state);

  @override
  Future<void> markFinished(String id, int endedAt) => db.markFinished(id, endedAt);

  @override
  Future<void> discardRun(String id) => db.discardRun(id);

  @override
  Stream<RunSummary?> watchRun(String id) {
    return db.watchRun(id).map((r) => r == null ? null : _toSummary(r));
  }

  @override
  Stream<List<RunSummary>> watchRecentRuns({int limit = 10}) {
    return db.watchRecentRuns(limit: limit).map((rows) => rows.map(_toSummary).toList());
  }

  @override
  Future<void> wipe() => db.wipe();
}
