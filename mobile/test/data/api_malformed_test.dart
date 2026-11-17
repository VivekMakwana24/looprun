import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:looprun/data/models/api_exception.dart';
import 'package:looprun/data/models/models.dart';
import 'package:looprun/data/services/api_service.dart';
import 'package:looprun/data/upload/backoff.dart';
import 'package:looprun/data/upload/upload_queue.dart';
import 'package:looprun/ui/auth/auth_view_model.dart';

/// Answers every request with 200 and a fixed body.
class BodyAdapter implements HttpClientAdapter {
  BodyAdapter(this.body);
  final String body;

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    return ResponseBody.fromString(body, 200, headers: {
      Headers.contentTypeHeader: ['application/json'],
    });
  }

  @override
  void close({bool force = false}) {}
}

DioApiService api(String body) => DioApiService(
      baseUrl: 'http://test',
      tokenProvider: () => 'tok',
      dio: Dio(BaseOptions(baseUrl: 'http://test/v1'))..httpClientAdapter = BodyAdapter(body),
    );

void main() {
  test('an answer of the wrong shape is "malformed", not "no connection" (review follow-up 7)', () async {
    try {
      await api('{"cells": "nope"}').getCells('1,2,3,4');
      fail('expected an ApiException');
    } on ApiException catch (e) {
      expect(e.malformed, isTrue);
      expect(e.isNetwork, isFalse);
      expect(e.message, unexpectedAnswerMessage);
    }
  });

  test('a body that is not JSON is malformed too', () async {
    try {
      await api('<html>proxy error</html>').weeklyLeaderboard();
      fail('expected an ApiException');
    } on ApiException catch (e) {
      expect(e.malformed, isTrue);
      expect(e.isNetwork, isFalse);
    }
  });

  test('sign-in says the answer was unexpected, not that the server cannot be reached', () {
    final text = signInErrorText(const ApiException.malformed(unexpectedAnswerMessage));
    expect(text, isNot(contains("Can't reach")));
    expect(text, contains('unexpected answer'));
  });

  test('an unreadable upload answer gives up like a server error, it is not retried for ever', () async {
    final store = _Store();
    final queue = UploadQueue(
      store: store,
      api: _MalformedRuns(),
      policy: const BackoffPolicy(maxAttempts: 2),
      nowMs: () => 0,
    );
    await queue.tick();
    expect(store.job.stage, UploadStage.queued);
    store.job = store.job.copyWith(nextAttemptAt: 0);
    await queue.tick();
    expect(store.job.stage, UploadStage.failed);
  });
}

class _MalformedRuns implements RunsApi {
  @override
  Future<RunStatus> uploadRun(RunUpload run) async => throw const ApiException.malformed('x');

  @override
  Future<RunStatus> getRun(String id) async => throw const ApiException.malformed('x');
}

class _Store implements UploadStore {
  UploadJob job = const UploadJob(runId: 'r1', stage: UploadStage.queued);

  @override
  Future<List<UploadJob>> activeJobs() async => job.stage == UploadStage.queued ? [job] : [];

  @override
  Future<UploadJob?> getJob(String runId) async => job;

  @override
  Future<void> saveJob(UploadJob j) async => job = j;

  @override
  Future<RunUpload> buildPayload(String runId) async =>
      RunUpload(id: runId, startedAt: 0, endedAt: 1, fixes: const []);
}
