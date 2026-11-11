import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:looprun/data/db/app_database.dart';
import 'package:looprun/data/models/models.dart';
import 'package:looprun/data/db/drift_run_store.dart';
import 'package:looprun/data/upload/drift_upload_store.dart';
import 'package:looprun/data/upload/upload_queue.dart';
import 'package:looprun/domain/recorder/run_recorder.dart';

import '../fakes/fakes.dart';

/// The real Drift stores on an in-memory SQLite database, two accounts on one phone.
void main() {
  late AppDatabase db;
  String? user;
  late DriftRunStore runs;
  late DriftUploadStore uploads;

  GeoFix fix(double lat, int t) => GeoFix(lat: lat, lng: 8.7, t: t, acc: 5);

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    user = 'A';
    runs = DriftRunStore(db, () => user);
    uploads = DriftUploadStore(db, () => user);
  });

  tearDown(() async {
    await db.close();
  });

  Future<void> record(String id) async {
    await runs.createRun(id, 1);
    await runs.addFix(id, fix(50.0, 10));
    await runs.addFix(id, fix(50.001, 20));
    await runs.markFinished(id, 30);
  }

  test("B cannot see, list, fetch or upload A's run", () async {
    await record('run-a');

    user = 'B';
    expect(await runs.runById('run-a'), isNull);
    expect(await runs.fixesFor('run-a'), isEmpty);
    expect(await runs.unfinishedRun(), isNull);
    expect(await runs.watchRecentRuns().first, isEmpty);
    expect(await runs.watchRun('run-a').first, isNull);
    expect(await uploads.activeJobs(), isEmpty);
    expect(await uploads.getJob('run-a'), isNull);
    await expectLater(uploads.buildPayload('run-a'), throwsStateError);

    user = 'A';
    expect((await runs.runById('run-a'))!.state, 'finished');
    expect((await uploads.activeJobs()).single.runId, 'run-a');
    expect((await uploads.buildPayload('run-a')).fixes.length, 2);
  });

  test("B's writes cannot touch A's run", () async {
    await record('run-a');
    user = 'B';
    await runs.setRunState('run-a', 'recording');
    await runs.discardRun('run-a');
    await uploads.saveJob(const UploadJob(runId: 'run-a', stage: UploadStage.done));

    user = 'A';
    expect((await runs.runById('run-a'))!.state, 'finished');
    expect((await runs.fixesFor('run-a')).length, 2);
    expect((await uploads.getJob('run-a'))!.stage, UploadStage.queued);
  });

  test('signed out: reads are empty and writes are refused', () async {
    await record('run-a');
    user = null;
    expect(await runs.runById('run-a'), isNull);
    expect(await uploads.activeJobs(), isEmpty);
    await expectLater(runs.createRun('x', 1), throwsStateError);
    await expectLater(runs.addFix('run-a', fix(50, 1)), throwsStateError);
  });

  test('wipe removes the signed-in account only', () async {
    await record('run-a');
    user = 'B';
    await record('run-b');
    await runs.wipe();
    expect(await runs.runById('run-b'), isNull);
    user = 'A';
    expect(await runs.runById('run-a'), isNotNull);
    expect((await runs.fixesFor('run-a')).length, 2);
  });

  test("sign out, sign in as B: A's queued run is never uploaded", () async {
    await record('run-a');
    final api = FakeApiService();
    var now = 1000;
    final queue = UploadQueue(
      store: uploads,
      api: api,
      nowMs: () => now,
      currentUserId: () => user,
    );

    user = null;
    expect(await queue.tick(), 0);
    user = 'B';
    expect(await queue.tick(), 0);
    expect(api.uploadedIds, isEmpty);

    user = 'A';
    await queue.tick();
    expect(api.uploadedIds, ['run-a']);
  });

  test('upgrade from schema 1 keeps old rows but gives them to nobody', () async {
    final old = AppDatabase(NativeDatabase.memory(setup: (raw) {
      raw.execute('CREATE TABLE runs (id TEXT NOT NULL PRIMARY KEY, started_at INTEGER NOT NULL, '
          "ended_at INTEGER NULL, state TEXT NOT NULL DEFAULT 'recording', "
          "upload TEXT NOT NULL DEFAULT 'none', attempts INTEGER NOT NULL DEFAULT 0, "
          'next_attempt_at INTEGER NOT NULL DEFAULT 0, last_error TEXT NULL, result_json TEXT NULL)');
      raw.execute('CREATE TABLE fixes (id INTEGER PRIMARY KEY AUTOINCREMENT, run_id TEXT NOT NULL, '
          'lat REAL NOT NULL, lng REAL NOT NULL, t INTEGER NOT NULL, acc REAL NOT NULL, '
          'is_mock INTEGER NOT NULL DEFAULT 0)');
      raw.execute("INSERT INTO runs (id, started_at, state, upload) VALUES ('legacy', 1, 'finished', 'queued')");
      raw.execute("INSERT INTO fixes (run_id, lat, lng, t, acc) VALUES ('legacy', 50, 8, 1, 5)");
      raw.execute('PRAGMA user_version = 1');
    }));
    final store = DriftRunStore(old, () => 'A');
    final up = DriftUploadStore(old, () => 'A');

    // Opening runs the migration. The legacy row is there but belongs to no account.
    expect(await store.runById('legacy'), isNull);
    expect(await up.activeJobs(), isEmpty);
    final legacy = await old.customSelect("SELECT user_id FROM runs WHERE id = 'legacy'").getSingle();
    expect(legacy.read<String>('user_id'), '');

    // And the upgraded database works for new data.
    await store.createRun('new', 5);
    expect((await store.runById('new'))!.id, 'new');
    await old.close();
  });

  test('if the account changes while the queue is busy, the remaining jobs are not sent', () async {
    await record('run-1');
    await record('run-2');
    final sent = <String>[];
    final api = _SwitchingApi(onUpload: (id) {
      sent.add(id);
      user = 'B'; // B signs in right after the first upload
    });
    final queue = UploadQueue(store: uploads, api: api, currentUserId: () => user);

    await queue.tick();
    expect(sent, ['run-1'], reason: 'run-2 must not go out once B is signed in');

    // The result of run-1 could not be saved under B, so it stays queued for A; uploads are
    // idempotent (client-generated id), so sending it again later is harmless.
    user = 'A';
    expect((await uploads.activeJobs()).map((j) => j.runId).toSet(), {'run-1', 'run-2'});
  });
}

class _SwitchingApi implements RunsApi {
  _SwitchingApi({required this.onUpload});
  final void Function(String id) onUpload;

  @override
  Future<RunStatus> uploadRun(RunUpload run) async {
    onUpload(run.id);
    return RunStatus(id: run.id, status: 'accepted');
  }

  @override
  Future<RunStatus> getRun(String id) async => RunStatus(id: id, status: 'accepted');
}
