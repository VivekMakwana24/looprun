import 'package:drift/drift.dart';

part 'app_database.g.dart';

/// One row per recorded run.
/// state: recording | paused | finished
/// upload: none | queued | processing | done | failed
@DataClassName('RunRow')
class Runs extends Table {
  TextColumn get id => text()();

  /// The account that recorded the run. Rows from before accounts were tracked have ''; they belong to
  /// nobody and are never shown or uploaded.
  TextColumn get userId => text().withDefault(const Constant(''))();
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
  TextColumn get userId => text().withDefault(const Constant(''))();
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
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) => m.createAll(),
        onUpgrade: (m, from, to) async {
          if (from < 2) {
            // Version 2 ties every run and fix to an account. Old rows get '' and stay unreachable.
            await m.addColumn(runs, runs.userId);
            await m.addColumn(fixes, fixes.userId);
          }
        },
      );

  Future<void> createRun(String userId, String id, int startedAt) {
    return into(runs).insert(RunsCompanion.insert(id: id, startedAt: startedAt, userId: Value(userId)));
  }

  Future<void> addFix({
    required String userId,
    required String runId,
    required double lat,
    required double lng,
    required int t,
    required double acc,
    required bool isMock,
  }) {
    return into(fixes).insert(FixesCompanion.insert(
      runId: runId,
      userId: Value(userId),
      lat: lat,
      lng: lng,
      t: t,
      acc: acc,
      isMock: Value(isMock),
    ));
  }

  Future<List<FixRow>> fixesFor(String userId, String runId) {
    return (select(fixes)
          ..where((f) => f.runId.equals(runId) & f.userId.equals(userId))
          ..orderBy([(f) => OrderingTerm.asc(f.t)]))
        .get();
  }

  Future<RunRow?> runById(String userId, String id) {
    return (select(runs)..where((r) => r.id.equals(id) & r.userId.equals(userId))).getSingleOrNull();
  }

  Stream<RunRow?> watchRun(String userId, String id) {
    return (select(runs)..where((r) => r.id.equals(id) & r.userId.equals(userId))).watchSingleOrNull();
  }

  /// Runs that were being recorded when the app died.
  Future<RunRow?> unfinishedRun(String userId) {
    return (select(runs)
          ..where((r) => r.state.isIn(['recording', 'paused']) & r.userId.equals(userId))
          ..orderBy([(r) => OrderingTerm.desc(r.startedAt)])
          ..limit(1))
        .getSingleOrNull();
  }

  Future<void> setRunState(String userId, String id, String state) {
    return (update(runs)..where((r) => r.id.equals(id) & r.userId.equals(userId)))
        .write(RunsCompanion(state: Value(state)));
  }

  /// Marks the run complete locally and queues it for upload.
  Future<void> markFinished(String userId, String id, int endedAt) {
    return (update(runs)..where((r) => r.id.equals(id) & r.userId.equals(userId))).write(RunsCompanion(
      state: const Value('finished'),
      upload: const Value('queued'),
      endedAt: Value(endedAt),
    ));
  }

  Future<void> discardRun(String userId, String id) async {
    await (delete(fixes)..where((f) => f.runId.equals(id) & f.userId.equals(userId))).go();
    await (delete(runs)..where((r) => r.id.equals(id) & r.userId.equals(userId))).go();
  }

  Future<List<RunRow>> activeUploads(String userId) {
    return (select(runs)
          ..where((r) => r.upload.isIn(['queued', 'processing']) & r.userId.equals(userId)))
        .get();
  }

  Future<void> writeUpload(
    String userId,
    String id, {
    required String upload,
    required int attempts,
    required int nextAttemptAt,
    String? lastError,
    String? resultJson,
  }) {
    return (update(runs)..where((r) => r.id.equals(id) & r.userId.equals(userId))).write(RunsCompanion(
      upload: Value(upload),
      attempts: Value(attempts),
      nextAttemptAt: Value(nextAttemptAt),
      lastError: Value(lastError),
      resultJson: Value(resultJson),
    ));
  }

  Stream<List<RunRow>> watchRecentRuns(String userId, {int limit = 20}) {
    return (select(runs)
          ..where((r) => r.state.equals('finished') & r.userId.equals(userId))
          ..orderBy([(r) => OrderingTerm.desc(r.startedAt)])
          ..limit(limit))
        .watch();
  }

  /// Used when the account is deleted: removes that account's data only.
  Future<void> wipe(String userId) async {
    await (delete(fixes)..where((f) => f.userId.equals(userId))).go();
    await (delete(runs)..where((r) => r.userId.equals(userId))).go();
  }
}
