import 'dart:convert';

import '../../domain/recorder/run_recorder.dart';
import '../models/models.dart';
import 'app_database.dart';
import 'run_store.dart';

class DriftRunStore implements RunStore {
  DriftRunStore(this.db, this._currentUserId);
  final AppDatabase db;
  final String? Function() _currentUserId;

  /// The signed-in account. Writes without one are refused; reads see nothing.
  String get _uid {
    final id = _currentUserId();
    if (id == null || id.isEmpty) throw StateError('Not signed in');
    return id;
  }

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
  Future<void> createRun(String id, int startedAt) => db.createRun(_uid, id, startedAt);

  @override
  Future<void> addFix(String runId, GeoFix fix) {
    return db.addFix(
      userId: _uid,
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
    final uid = _currentUserId();
    if (uid == null || uid.isEmpty) return const [];
    final rows = await db.fixesFor(uid, runId);
    return rows
        .map((f) => Fix(lat: f.lat, lng: f.lng, t: f.t, acc: f.acc, mock: f.isMock))
        .toList();
  }

  @override
  Future<RunSummary?> runById(String id) async {
    final uid = _currentUserId();
    if (uid == null || uid.isEmpty) return null;
    final r = await db.runById(uid, id);
    return r == null ? null : _toSummary(r);
  }

  @override
  Future<RunSummary?> unfinishedRun() async {
    final uid = _currentUserId();
    if (uid == null || uid.isEmpty) return null;
    final r = await db.unfinishedRun(uid);
    return r == null ? null : _toSummary(r);
  }

  @override
  Future<void> setRunState(String id, String state) => db.setRunState(_uid, id, state);

  @override
  Future<void> markFinished(String id, int endedAt) => db.markFinished(_uid, id, endedAt);

  @override
  Future<void> discardRun(String id) => db.discardRun(_uid, id);

  @override
  Stream<RunSummary?> watchRun(String id) {
    final uid = _currentUserId();
    if (uid == null || uid.isEmpty) return Stream.value(null);
    return db.watchRun(uid, id).map((r) => r == null ? null : _toSummary(r));
  }

  @override
  Stream<List<RunSummary>> watchRecentRuns({int limit = 10}) {
    final uid = _currentUserId();
    if (uid == null || uid.isEmpty) return Stream.value(const <RunSummary>[]);
    return db.watchRecentRuns(uid, limit: limit).map((rows) => rows.map(_toSummary).toList());
  }

  @override
  Future<void> wipe() => db.wipe(_uid);
}
