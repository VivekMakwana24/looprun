import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;

import '../models/api_exception.dart';
import '../models/models.dart';
import '../upload/upload_queue.dart';

/// Every call to the Looprun server (docs/CONTRACT.openapi.yaml). Stateless apart from the token lookup;
/// repositories decide what to keep. Tests use a fake implementation.
/// Text of an [ApiException] without a status code (no answer from the server).
const String networkErrorMessage = "Can't reach the server. Check your connection.";

/// Text of an [ApiException.malformed]: the server answered with something the app cannot read.
const String unexpectedAnswerMessage = 'The server sent an answer this version of Looprun cannot read.';

abstract class ApiService implements RunsApi {
  Future<Session> authGoogle(String idToken);

  /// bbox is "minLng,minLat,maxLng,maxLat"; the server rejects sides over 0.2 degrees.
  Future<List<Cell>> getCells(String bbox);

  Future<Leaderboard> weeklyLeaderboard();

  Future<void> putHomeZones(List<HomeZone> zones);

  /// Starts (days > 0) or ends (0) a decay freeze. A 409 means the quota would be exceeded.
  Future<FreezeStatus> setFreeze(int days);

  /// The caller's own settings: name, home zones, freeze state and quota (D10).
  Future<MeInfo> getMe();

  Future<void> deleteAccount();

  /// kind is "run" or "cell"; reason is at most 500 characters.
  Future<void> report({required String kind, required String targetId, required String reason});
}

class DioApiService implements ApiService {
  DioApiService({
    required String baseUrl,
    required String? Function() tokenProvider,
    void Function()? onUnauthorized,
    Dio? dio,
  })  : _onUnauthorized = onUnauthorized,
        _dio = dio ??
            Dio(BaseOptions(
              baseUrl: '$baseUrl/v1',
              connectTimeout: const Duration(seconds: 15),
              sendTimeout: const Duration(seconds: 60),
              receiveTimeout: const Duration(seconds: 30),
              contentType: 'application/json',
            )) {
    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) {
        final token = tokenProvider();
        if (token != null && token.isNotEmpty) {
          options.headers['Authorization'] = 'Bearer $token';
        }
        handler.next(options);
      },
    ));
  }

  final Dio _dio;
  final void Function()? _onUnauthorized;

  Future<T> _guard<T>(Future<T> Function() call) async {
    try {
      return await call();
    } on DioException catch (e) {
      if (kDebugMode) {
        // Debug builds only: the real cause behind "Can't reach the server" (refused, timeout,
        // cleartext blocked...). Method, URL and error only: never headers, so never the token.
        debugPrint('Looprun API ${e.requestOptions.method} ${e.requestOptions.uri} failed: '
            '${e.type.name} ${e.response?.statusCode ?? ''} ${e.error ?? e.message ?? ''}');
      }
      if (e.error is FormatException) throw const ApiException.malformed(unexpectedAnswerMessage);
      final code = e.response?.statusCode;
      if (code == 401) _onUnauthorized?.call();
      throw ApiException(code, _messageOf(e));
    } on ApiException {
      rethrow;
    } on TypeError {
      throw const ApiException.malformed(unexpectedAnswerMessage);
    } on FormatException {
      throw const ApiException.malformed(unexpectedAnswerMessage);
    }
  }

  String _messageOf(DioException e) {
    final data = e.response?.data;
    if (data is Map && data['detail'] is String) return data['detail'] as String;
    if (e.response == null) return networkErrorMessage;
    return 'The server answered with an error (${e.response?.statusCode}).';
  }

  Map<String, dynamic> _map(Object? data) => (data as Map).cast<String, dynamic>();

  @override
  Future<Session> authGoogle(String idToken) => _guard(() async {
        final res = await _dio.post('/auth/google', data: {'id_token': idToken});
        return Session.fromJson(_map(res.data));
      });

  @override
  Future<RunStatus> uploadRun(RunUpload run) => _guard(() async {
        final res = await _dio.post('/runs', data: run.toJson());
        return RunStatus.fromJson(_map(res.data));
      });

  @override
  Future<RunStatus> getRun(String id) => _guard(() async {
        final res = await _dio.get('/runs/$id');
        return RunStatus.fromJson(_map(res.data));
      });

  @override
  Future<List<Cell>> getCells(String bbox) => _guard(() async {
        final res = await _dio.get('/cells', queryParameters: {'bbox': bbox});
        final list = (_map(res.data)['cells'] as List?) ?? const [];
        return list.map((e) => Cell.fromJson((e as Map).cast<String, dynamic>())).toList();
      });

  @override
  Future<Leaderboard> weeklyLeaderboard() => _guard(() async {
        final res = await _dio.get('/leaderboard/weekly');
        return Leaderboard.fromJson(_map(res.data));
      });

  @override
  Future<void> putHomeZones(List<HomeZone> zones) => _guard(() async {
        await _dio.put('/me/home-zones', data: {'zones': zones.map((z) => z.toJson()).toList()});
      });

  @override
  Future<FreezeStatus> setFreeze(int days) => _guard(() async {
        final res = await _dio.post('/me/freeze', data: {'days': days});
        return FreezeStatus.fromJson(_map(res.data));
      });

  @override
  Future<MeInfo> getMe() => _guard(() async {
        final res = await _dio.get('/me');
        return MeInfo.fromJson(_map(res.data));
      });

  @override
  Future<void> deleteAccount() => _guard(() async {
        await _dio.delete('/me');
      });

  @override
  Future<void> report({required String kind, required String targetId, required String reason}) =>
      _guard(() async {
        await _dio.post('/reports', data: {'kind': kind, 'target_id': targetId, 'reason': reason});
      });
}
