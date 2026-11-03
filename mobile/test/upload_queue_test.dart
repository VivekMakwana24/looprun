import 'package:flutter_test/flutter_test.dart';
import 'package:looprun/data/api/api_exception.dart';
import 'package:looprun/data/api/models.dart';
import 'package:looprun/data/upload/backoff.dart';
import 'package:looprun/data/upload/upload_queue.dart';

class FakeStore implements UploadStore {
  final Map<String, UploadJob> jobs = {};

  @override
  Future<List<UploadJob>> activeJobs() async => jobs.values
      .where((j) => j.stage == UploadStage.queued || j.stage == UploadStage.processing)
      .toList();

  @override
  Future<UploadJob?> getJob(String runId) async => jobs[runId];

  @override
  Future<void> saveJob(UploadJob job) async {
    jobs[job.runId] = job;
  }

  @override
  Future<RunUpload> buildPayload(String runId) async =>
      RunUpload(id: runId, startedAt: 0, endedAt: 1000, fixes: const []);
}

class FakeApi implements RunsApi {
  final List<Object> uploadResults = [];
  final List<Object> getResults = [];
  final List<String> uploadedIds = [];
  int gets = 0;

  Object _next(List<Object> list) => list.length > 1 ? list.removeAt(0) : list.first;

  @override
  Future<RunStatus> uploadRun(RunUpload run) async {
    uploadedIds.add(run.id);
    final r = _next(uploadResults);
    if (r is ApiException) throw r;
    return r as RunStatus;
  }

  @override
  Future<RunStatus> getRun(String id) async {
    gets++;
    final r = _next(getResults);
    if (r is ApiException) throw r;
    return r as RunStatus;
  }
}

RunStatus st(String status) => RunStatus(id: 'r1', status: status);

void main() {
  late int now;
  late FakeStore store;
  late FakeApi api;
  late UploadQueue queue;

  UploadQueue make({BackoffPolicy policy = const BackoffPolicy()}) => UploadQueue(
        store: store,
        api: api,
        policy: policy,
        pollInterval: const Duration(seconds: 3),
        nowMs: () => now,
      );

  setUp(() {
    now = 100000;
    store = FakeStore();
    api = FakeApi();
    store.jobs['r1'] = const UploadJob(runId: 'r1', stage: UploadStage.queued);
    queue = make();
  });

  test('upload then poll until the run is no longer processing', () async {
    api.uploadResults.add(st('processing'));
    api.getResults
      ..add(st('processing'))
      ..add(st('accepted'));

    expect(await queue.tick(), 1);
    expect(store.jobs['r1']!.stage, UploadStage.processing);
    expect(api.uploadedIds, ['r1']);

    // Not due yet: nothing happens.
    now += 1000;
    expect(await queue.tick(), 0);
    expect(api.gets, 0);

    now += 3000;
    await queue.tick();
    expect(api.gets, 1);
    expect(store.jobs['r1']!.stage, UploadStage.processing);

    now += 3000;
    await queue.tick();
    expect(store.jobs['r1']!.stage, UploadStage.done);
    expect(store.jobs['r1']!.result!.status, 'accepted');
  });

  test('an immediate final answer finishes the job', () async {
    api.uploadResults.add(st('pending_review'));
    await queue.tick();
    expect(store.jobs['r1']!.stage, UploadStage.done);
    expect(store.jobs['r1']!.result!.status, 'pending_review');
  });

  test('network errors back off exponentially and then succeed', () async {
    api.uploadResults
      ..add(const ApiException(null, 'offline'))
      ..add(const ApiException(503, 'busy'))
      ..add(st('accepted'));

    await queue.tick();
    var job = store.jobs['r1']!;
    expect(job.stage, UploadStage.queued);
    expect(job.attempts, 1);
    expect(job.nextAttemptAt, now + 2000);

    // Too early.
    now += 1999;
    expect(await queue.tick(), 0);

    now += 1;
    await queue.tick();
    job = store.jobs['r1']!;
    expect(job.attempts, 2);
    expect(job.nextAttemptAt, now + 4000);

    now += 4000;
    await queue.tick();
    expect(store.jobs['r1']!.stage, UploadStage.done);
    // Same client-generated id every time (idempotent upload).
    expect(api.uploadedIds, ['r1', 'r1', 'r1']);
  });

  test('a validation error is not retried', () async {
    api.uploadResults.add(const ApiException(422, 'bad fixes'));
    await queue.tick();
    final job = store.jobs['r1']!;
    expect(job.stage, UploadStage.failed);
    expect(job.lastError, 'bad fixes');
    now += 1000000;
    expect(await queue.tick(), 0);
  });

  test('gives up after maxAttempts', () async {
    queue = make(policy: const BackoffPolicy(maxAttempts: 2));
    api.uploadResults.add(const ApiException(null, 'offline'));
    await queue.tick();
    expect(store.jobs['r1']!.stage, UploadStage.queued);
    now += 10000;
    await queue.tick();
    expect(store.jobs['r1']!.stage, UploadStage.failed);
  });

  test('requeue puts a failed job back and it can then succeed', () async {
    api.uploadResults
      ..add(const ApiException(422, 'bad'))
      ..add(st('accepted'));
    await queue.tick();
    expect(store.jobs['r1']!.stage, UploadStage.failed);
    await queue.requeue('r1');
    expect(store.jobs['r1']!.stage, UploadStage.queued);
    expect(store.jobs['r1']!.attempts, 0);
    await queue.tick();
    expect(store.jobs['r1']!.stage, UploadStage.done);
  });

  test('a restarted queue continues from the persisted job', () async {
    api.uploadResults.add(st('processing'));
    await queue.tick();
    // New queue instance, same store: simulates an app restart.
    final restarted = make();
    api.getResults.add(st('accepted'));
    now += 5000;
    await restarted.tick();
    expect(store.jobs['r1']!.stage, UploadStage.done);
    expect(api.uploadedIds.length, 1);
  });
}
