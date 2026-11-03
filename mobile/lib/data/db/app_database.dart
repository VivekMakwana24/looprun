import 'package:drift/drift.dart';

part 'app_database.g.dart';

/// One row per recorded run.
/// state: recording | paused | finished
/// upload: none | queued | processing | done | failed
@DataClassName('RunRow')
class Runs extends Table {
  TextColumn get id => text()();
  IntColumn get startedAt => integer()();
  IntColumn get endedAt => integer().nullable()();
  TextColumn get state => text().withDefault(const Constant('recording'))();
  TextColumn get upload => text().withDefault(const Constant('none'))();
  IntColumn get attempts => integer().withDefault(const Constant(0))();
  IntColumn get nextAttemptAt => integer().withDefault(const Constant(0))();
  TextColumn get lastError => text().nullable()();
  TextColumn get resultJson => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Every GPS fix is inserted here as soon as it arrives.
@DataClassName('FixRow')
class Fixes extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get runId => text()();
  RealColumn get lat => real()();
  RealColumn get lng => real()();
  IntColumn get t => integer()();
  RealColumn get acc => real()();
  BoolColumn get isMock => boolean().withDefault(const Constant(false))();
}

@DriftDatabase(tables: [Runs, Fixes])
class AppDatabase extends _$AppDatabase {
  AppDatabase(QueryExecutor e) : super(e);

  @override
  int get schemaVersion => 1;

  Future<void> createRun(String id, int startedAt) {
    return into(runs).insert(RunsCompanion.insert(id: id, startedAt: startedAt));
  }

  Future<void> addFix({
    required String runId,
    required double lat,
    required double lng,
    required int t,
    required double acc,
    required bool isMock,
  }) {
    return into(fixes).insert(FixesCompanion.insert(
      runId: runId,
      lat: lat,
      lng: lng,
      t: t,
      acc: acc,
      isMock: Value(isMock),
    ));
  }

  Future<List<FixRow>> fixesFor(String runId) {
    return (select(fixes)
          ..where((f) => f.runId.equals(runId))
          ..orderBy([(f) => OrderingTerm.asc(f.t)]))
        .get();
  }

  Future<RunRow?> runById(String id) {
    return (select(runs)..where((r) => r.id.equals(id))).getSingleOrNull();
  }

  Stream<RunRow?> watchRun(String id) {
    return (select(runs)..where((r) => r.id.equals(id))).watchSingleOrNull();
  }

  /// Runs that were being recorded when the app died.
  Future<RunRow?> unfinishedRun() {
    return (select(runs)
          ..where((r) => r.state.isIn(['recording', 'paused']))
          ..orderBy([(r) => OrderingTerm.desc(r.startedAt)])
          ..limit(1))
        .getSingleOrNull();
  }

  Future<void> setRunState(String id, String state) {
    return (update(runs)..where((r) => r.id.equals(id)))
        .write(RunsCompanion(state: Value(state)));
  }

  /// Marks the run complete locally and queues it for upload.
  Future<void> markFinished(String id, int endedAt) {
    return (update(runs)..where((r) => r.id.equals(id))).write(RunsCompanion(
      state: const Value('finished'),
      upload: const Value('queued'),
      endedAt: Value(endedAt),
    ));
  }

  Future<void> discardRun(String id) async {
    await (delete(fixes)..where((f) => f.runId.equals(id))).go();
    await (delete(runs)..where((r) => r.id.equals(id))).go();
  }

  Future<List<RunRow>> activeUploads() {
    return (select(runs)..where((r) => r.upload.isIn(['queued', 'processing']))).get();
  }

  Future<void> writeUpload(
    String id, {
    required String upload,
    required int attempts,
    required int nextAttemptAt,
    String? lastError,
    String? resultJson,
  }) {
    return (update(runs)..where((r) => r.id.equals(id))).write(RunsCompanion(
      upload: Value(upload),
      attempts: Value(attempts),
      nextAttemptAt: Value(nextAttemptAt),
      lastError: Value(lastError),
      resultJson: Value(resultJson),
    ));
  }

  Stream<List<RunRow>> watchRecentRuns({int limit = 20}) {
    return (select(runs)
          ..where((r) => r.state.equals('finished'))
          ..orderBy([(r) => OrderingTerm.desc(r.startedAt)])
          ..limit(limit))
        .watch();
  }

  /// Used when the account is deleted.
  Future<void> wipe() async {
    await delete(fixes).go();
    await delete(runs).go();
  }
}
