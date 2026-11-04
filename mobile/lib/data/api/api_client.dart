import 'package:dio/dio.dart';

import '../upload/upload_queue.dart';
import 'api_exception.dart';
import 'models.dart';

class ApiClient implements RunsApi {
  ApiClient({
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

  /// bbox is "minLng,minLat,maxLng,maxLat"; the server rejects sides over 0.2 degrees.
  Future<List<Cell>> getCells(String bbox) => _guard(() async {
        final res = await _dio.get('/cells', queryParameters: {'bbox': bbox});
        final list = (_map(res.data)['cells'] as List?) ?? const [];
        return list.map((e) => Cell.fromJson((e as Map).cast<String, dynamic>())).toList();
      });

  Future<Leaderboard> weeklyLeaderboard() => _guard(() async {
        final res = await _dio.get('/leaderboard/weekly');
        return Leaderboard.fromJson(_map(res.data));
      });

  Future<void> putHomeZones(List<HomeZone> zones) => _guard(() async {
        await _dio.put('/me/home-zones', data: {'zones': zones.map((z) => z.toJson()).toList()});
      });

  /// Returns freeze_until (epoch ms) or null when no freeze is active.
  Future<int?> setFreeze(int days) => _guard(() async {
        final res = await _dio.post('/me/freeze', data: {'days': days});
        final v = _map(res.data)['freeze_until'];
        return v is num ? v.toInt() : null;
      });

  Future<void> deleteAccount() => _guard(() async {
        await _dio.delete('/me');
      });
}
