import 'package:dio/dio.dart';

import '../models/api_exception.dart';
import '../models/models.dart';
import '../upload/upload_queue.dart';

/// Every call to the Looprun server (docs/CONTRACT.openapi.yaml). Stateless apart from the token lookup;
/// repositories decide what to keep. Tests use a fake implementation.
abstract class ApiService implements RunsApi {
  Future<Session> authGoogle(String idToken);

  /// bbox is "minLng,minLat,maxLng,maxLat"; the server rejects sides over 0.2 degrees.
  Future<List<Cell>> getCells(String bbox);

  Future<Leaderboard> weeklyLeaderboard();

  Future<void> putHomeZones(List<HomeZone> zones);

  /// Returns freeze_until (epoch ms) or null when no freeze is active.
  Future<int?> setFreeze(int days);

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
      final code = e.response?.statusCode;
      if (code == 401) _onUnauthorized?.call();
      throw ApiException(code, _messageOf(e));
    } on ApiException {
      rethrow;
    } on TypeError catch (e) {
      throw ApiException(null, 'Unexpected response: $e');
    } on FormatException catch (e) {
      throw ApiException(null, 'Unexpected response: ${e.message}');
    }
  }

  String _messageOf(DioException e) {
    final data = e.response?.data;
    if (data is Map && data['detail'] is String) return data['detail'] as String;
    return e.message ?? 'Network error';
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
  Future<int?> setFreeze(int days) => _guard(() async {
        final res = await _dio.post('/me/freeze', data: {'days': days});
        final v = _map(res.data)['freeze_until'];
        return v is num ? v.toInt() : null;
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
