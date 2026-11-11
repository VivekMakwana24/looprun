import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:looprun/data/auth/session_expiry_policy.dart';
import 'package:looprun/data/models/models.dart';
import 'package:looprun/data/services/api_service.dart';
import 'package:looprun/data/upload/upload_queue.dart';

/// Answers every request with a fixed status; records what was asked.
class StatusAdapter implements HttpClientAdapter {
  StatusAdapter(this.status);
  int status;
  final List<RequestOptions> seen = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    seen.add(options);
    final body = status == 401
        ? jsonEncode({'detail': 'token expired'})
        : jsonEncode({'id': 'r1', 'status': 'accepted'});
    return ResponseBody.fromString(body, status, headers: {
      Headers.contentTypeHeader: ['application/json'],
    });
  }

  @override
  void close({bool force = false}) {}
}

class OneRunStore implements UploadStore {
  UploadJob job = const UploadJob(runId: 'r1', stage: UploadStage.queued);

  @override
  Future<List<UploadJob>> activeJobs() async =>
      job.stage == UploadStage.queued || job.stage == UploadStage.processing ? [job] : [];

  @override
  Future<UploadJob?> getJob(String runId) async => job;

  @override
  Future<void> saveJob(UploadJob j) async => job = j;

  @override
  Future<RunUpload> buildPayload(String runId) async =>
      RunUpload(id: runId, startedAt: 0, endedAt: 1000, fixes: const []);
}

void main() {
  late StatusAdapter adapter;
  late OneRunStore store;
  late bool recording;
  late int expired;
  late SessionExpiryPolicy policy;
  late UploadQueue queue;

  setUp(() {
    adapter = StatusAdapter(401);
    store = OneRunStore();
    recording = false;
    expired = 0;
    policy = SessionExpiryPolicy(
      isRecording: () => recording,
      lastStoppedAtMs: () => null,
      expire: () => expired++,
    );
    final dio = Dio(BaseOptions(baseUrl: 'http://test/v1', contentType: 'application/json'))
      ..httpClientAdapter = adapter;
    final api = DioApiService(
      baseUrl: 'http://test',
      tokenProvider: () => 'tok',
      onUnauthorized: policy.onUnauthorized,
      dio: dio,
    );
    queue = UploadQueue(store: store, api: api);
  });

  test('a 401 on upload goes Dio -> DioApiService -> policy and the job survives', () async {
    await queue.tick();

    expect(adapter.seen.single.headers['Authorization'], 'Bearer tok');
    expect(expired, 1, reason: 'the 401 reached the session policy through the real client');
    expect(store.job.stage, UploadStage.queued);
    expect(store.job.attempts, 0);
    expect(queue.isBlockedByAuth, isTrue);
  });

  test('a 401 while a run is recording does not sign out, but the upload still waits', () async {
    recording = true;
    await queue.tick();
    expect(expired, 0);
    expect(policy.hasDeferred, isTrue);
    expect(store.job.stage, UploadStage.queued);
  });

  test('after re-auth the queued run uploads with the new token', () async {
    await queue.tick();
    adapter.status = 200;
    queue.resumeAfterAuth();
    await queue.tick();
    expect(store.job.stage, UploadStage.done);
    expect(adapter.seen.length, 2);
  });
}
