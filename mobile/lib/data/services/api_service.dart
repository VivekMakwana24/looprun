import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show debugPrint, kDebugMode, visibleForTesting;

import '../models/api_exception.dart';
import '../models/models.dart';
import '../models/social_models.dart';
import '../upload/upload_queue.dart';
import 'social_api.dart';

/// Every call to the Looprun server (docs/CONTRACT.openapi.yaml). Stateless apart from the token lookup;
/// repositories decide what to keep. Tests use a fake implementation.
/// Text of an [ApiException] without a status code (no answer from the server).
const String networkErrorMessage = "Can't reach the server. Check your connection.";

/// Text of an [ApiException.malformed]: the server answered with something the app cannot read.
const String unexpectedAnswerMessage = 'The server sent an answer this version of Looprun cannot read.';

abstract class ApiService implements RunsApi, SocialApi {
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

  /// kind is run, cell, user, comment or run_card (Phase 1a); reason is at most 500 characters.
  Future<void> report({required String kind, required String targetId, required String reason});
}

class DioApiService implements ApiService {
  DioApiService({
    required String baseUrl,
    required String? Function() tokenProvider,
    void Function()? onUnauthorized,
    Dio? dio,
  })  : _onUnauthorized = onUnauthorized,
        _tokenProvider = tokenProvider,
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
  final String? Function() _tokenProvider;

  /// The token the next request would carry. For the provider-graph test only.
  @visibleForTesting
  String? debugCurrentToken() => _tokenProvider();

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
      throw ApiException(code, _messageOf(e), code: _codeOf(e));
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
    // Phase 1a routes: {"detail": {"code": ..., "message": ...}}.
    if (data is Map && data['detail'] is Map) {
      final m = (data['detail'] as Map)['message'];
      if (m is String && m.isNotEmpty) return m;
    }
    if (e.response == null) return networkErrorMessage;
    return 'The server answered with an error (${e.response?.statusCode}).';
  }

  String? _codeOf(DioException e) {
    final data = e.response?.data;
    if (data is Map && data['detail'] is Map) {
      final c = (data['detail'] as Map)['code'];
      if (c is String && c.isNotEmpty) return c;
    }
    return null;
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

  // ------------------------------------------------------------------ Phase 1a: social + battles

  static Map<String, dynamic> _page(String? cursor, int limit, [Map<String, dynamic>? more]) => {
        'limit': limit,
        if (cursor != null && cursor.isNotEmpty) 'cursor': cursor,
        ...?more,
      };

  static String _id(String id) => Uri.encodeComponent(id);

  @override
  Future<UserRef> renameMe(String displayName) => _guard(() async {
        final res = await _dio.patch('/me', data: {'display_name': displayName});
        return UserRef.fromJson((_map(res.data)['user'] as Map).cast<String, dynamic>());
      });

  @override
  Future<Profile> getProfile(String userId) => _guard(() async {
        final res = await _dio.get('/users/${_id(userId)}');
        return Profile.fromJson(_map(res.data));
      });

  @override
  Future<FollowState> follow(String userId) => _guard(() async {
        final res = await _dio.put('/users/${_id(userId)}/follow');
        return FollowState.fromJson(_map(res.data));
      });

  @override
  Future<FollowState> unfollow(String userId) => _guard(() async {
        final res = await _dio.delete('/users/${_id(userId)}/follow');
        return FollowState.fromJson(_map(res.data));
      });

  @override
  Future<PagedResult<UserListItem>> followers({String? cursor, int limit = 20}) => _guard(() async {
        final res = await _dio.get('/me/followers', queryParameters: _page(cursor, limit));
        return PagedResult.fromJson(_map(res.data), UserListItem.fromJson);
      });

  @override
  Future<PagedResult<UserListItem>> following({String? cursor, int limit = 20}) => _guard(() async {
        final res = await _dio.get('/me/following', queryParameters: _page(cursor, limit));
        return PagedResult.fromJson(_map(res.data), UserListItem.fromJson);
      });

  @override
  Future<List<UserListItem>> searchUsers(String query) => _guard(() async {
        final res = await _dio.get('/users/search', queryParameters: {'q': query});
        final list = (_map(res.data)['users'] as List?) ?? const [];
        return list.map((e) => UserListItem.fromJson((e as Map).cast<String, dynamic>())).toList();
      });

  @override
  Future<List<UserListItem>> rivals() => _guard(() async {
        final res = await _dio.get('/me/rivals');
        final list = (_map(res.data)['users'] as List?) ?? const [];
        return list.map((e) => UserListItem.fromJson((e as Map).cast<String, dynamic>())).toList();
      });

  @override
  Future<PagedResult<RunCard>> feed({String? cursor, int limit = 20}) => _guard(() async {
        final res = await _dio.get('/feed', queryParameters: _page(cursor, limit));
        return PagedResult.fromJson(_map(res.data), RunCard.fromJson);
      });

  @override
  Future<PagedResult<RunCard>> runHistory({String? cursor, int limit = 20, String? status}) =>
      _guard(() async {
        final res = await _dio.get('/runs',
            queryParameters: _page(cursor, limit, {if (status != null) 'status': status}));
        return PagedResult.fromJson(_map(res.data), RunCard.fromJson);
      });

  @override
  Future<KudosState> giveKudos(String runId) => _guard(() async {
        final res = await _dio.put('/runs/${_id(runId)}/kudos');
        return KudosState.fromJson(_map(res.data));
      });

  @override
  Future<KudosState> removeKudos(String runId) => _guard(() async {
        final res = await _dio.delete('/runs/${_id(runId)}/kudos');
        return KudosState.fromJson(_map(res.data));
      });

  @override
  Future<PagedResult<Comment>> comments(String runId, {String? cursor, int limit = 20}) =>
      _guard(() async {
        final res = await _dio.get('/runs/${_id(runId)}/comments', queryParameters: _page(cursor, limit));
        return PagedResult.fromJson(_map(res.data), Comment.fromJson);
      });

  @override
  Future<Comment> addComment(String runId, String text) => _guard(() async {
        final res = await _dio.post('/runs/${_id(runId)}/comments', data: {'text': text});
        return Comment.fromJson(_map(res.data));
      });

  @override
  Future<void> deleteComment(String runId, String commentId) => _guard(() async {
        await _dio.delete('/runs/${_id(runId)}/comments/${_id(commentId)}');
      });

  @override
  Future<BattleSummary> battleSummary() => _guard(() async {
        final res = await _dio.get('/battles/summary');
        return BattleSummary.fromJson(_map(res.data));
      });

  @override
  Future<Rivalry> rivalry({int days = 30}) => _guard(() async {
        final res = await _dio.get('/battles/rivalry', queryParameters: {'days': days});
        return Rivalry.fromJson(_map(res.data));
      });

  @override
  Future<List<LostCell>> takeBack() => _guard(() async {
        final res = await _dio.get('/battles/take-back');
        final list = (_map(res.data)['cells'] as List?) ?? const [];
        return list.map((e) => LostCell.fromJson((e as Map).cast<String, dynamic>())).toList();
      });

  @override
  Future<NotificationPage> notifications({String? cursor, int limit = 20}) => _guard(() async {
        final res = await _dio.get('/notifications', queryParameters: _page(cursor, limit));
        return NotificationPage.fromJson(_map(res.data));
      });

  @override
  Future<int> unreadCount() => _guard(() async {
        final res = await _dio.get('/notifications/unread-count');
        final v = _map(res.data)['unread_count'];
        return v is num ? v.toInt() : 0;
      });

  @override
  Future<void> markRead({List<String>? ids, bool all = false}) => _guard(() async {
        if (!all && (ids == null || ids.isEmpty)) return; // the server answers 422 to an empty list
        await _dio.post('/notifications/read', data: all ? {'all': true} : {'ids': ids ?? const <String>[]});
      });

  @override
  Future<void> blockUser(String userId) => _guard(() async {
        await _dio.put('/users/${_id(userId)}/block');
      });

  @override
  Future<void> unblockUser(String userId) => _guard(() async {
        await _dio.delete('/users/${_id(userId)}/block');
      });

  @override
  Future<PagedResult<UserRef>> blocks({String? cursor, int limit = 20}) => _guard(() async {
        final res = await _dio.get('/me/blocks', queryParameters: _page(cursor, limit));
        return PagedResult.fromJson(_map(res.data), UserRef.fromJson);
      });
}
