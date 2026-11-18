import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:looprun/data/models/api_exception.dart';
import 'package:looprun/data/services/api_service.dart';

import '../fakes/social_fixtures.dart';

class _Adapter implements HttpClientAdapter {
  int status = 200;
  Object? body = <String, dynamic>{};
  final List<RequestOptions> seen = [];

  RequestOptions get last => seen.last;

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    seen.add(options);
    return ResponseBody.fromString(body == null ? '' : jsonEncode(body), status, headers: {
      Headers.contentTypeHeader: ['application/json'],
    });
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  late _Adapter adapter;
  late DioApiService api;

  setUp(() {
    adapter = _Adapter();
    final dio = Dio(BaseOptions(baseUrl: 'http://test/v1', contentType: 'application/json'))..httpClientAdapter = adapter;
    api = DioApiService(baseUrl: 'http://test', tokenProvider: () => 'tok', dio: dio);
  });

  test('feed asks GET /feed with limit and cursor and reads the page', () async {
    adapter.body = {'items': [cardJson('r1')], 'next_cursor': 'abc'};
    final page = await api.feed(cursor: 'zzz');
    expect(adapter.last.method, 'GET');
    expect(adapter.last.path, '/feed');
    expect(adapter.last.queryParameters, {'limit': 20, 'cursor': 'zzz'});
    expect(adapter.last.headers['Authorization'], 'Bearer tok');
    expect(page.items.single.id, 'r1');
    expect(page.nextCursor, 'abc');

    await api.feed();
    expect(adapter.last.queryParameters, {'limit': 20}, reason: 'no cursor key on the first page');
  });

  test('run history passes the status filter', () async {
    adapter.body = {'items': [], 'next_cursor': null};
    await api.runHistory(status: 'pending_review');
    expect(adapter.last.path, '/runs');
    expect(adapter.last.queryParameters['status'], 'pending_review');
  });

  test('follow, unfollow, block, unblock use PUT and DELETE on the user', () async {
    adapter.body = {'is_following': true, 'followers_count': 3};
    expect((await api.follow('u 2')).followersCount, 3);
    expect(adapter.last.method, 'PUT');
    expect(adapter.last.path, '/users/u%202/follow', reason: 'ids are escaped');
    await api.unfollow('u2');
    expect(adapter.last.method, 'DELETE');
    expect(adapter.last.path, '/users/u2/follow');
    adapter
      ..status = 204
      ..body = null;
    await api.blockUser('u2');
    expect(adapter.last.method, 'PUT');
    expect(adapter.last.path, '/users/u2/block');
    await api.unblockUser('u2');
    expect(adapter.last.method, 'DELETE');
  });

  test('kudos and comments', () async {
    adapter.body = {'kudos_by_me': true, 'kudos_count': 1};
    await api.giveKudos('r1');
    expect(adapter.last.method, 'PUT');
    expect(adapter.last.path, '/runs/r1/kudos');
    await api.removeKudos('r1');
    expect(adapter.last.method, 'DELETE');

    adapter
      ..status = 201
      ..body = {'id': 'c1', 'run_id': 'r1', 'user': {'id': 'u1', 'name': 'Me'}, 'text': 'hi', 'created_at': 1, 'can_delete': true};
    final c = await api.addComment('r1', 'hi');
    expect(adapter.last.method, 'POST');
    expect(adapter.last.path, '/runs/r1/comments');
    expect(adapter.last.data, {'text': 'hi'});
    expect(c.canDelete, isTrue);

    adapter
      ..status = 204
      ..body = null;
    await api.deleteComment('r1', 'c1');
    expect(adapter.last.method, 'DELETE');
    expect(adapter.last.path, '/runs/r1/comments/c1');
  });

  test('rename sends display_name to PATCH /me', () async {
    adapter.body = {'user': {'id': 'u1', 'name': 'Mia K'}};
    final u = await api.renameMe('Mia K');
    expect(adapter.last.method, 'PATCH');
    expect(adapter.last.path, '/me');
    expect(adapter.last.data, {'display_name': 'Mia K'});
    expect(u.name, 'Mia K');
  });

  test('search, rivals, battles, take-back, notifications', () async {
    adapter.body = {'users': [{'id': 'u2', 'name': 'Mia', 'is_following': false, 'follows_me': true}]};
    final found = await api.searchUsers('mi');
    expect(adapter.last.path, '/users/search');
    expect(adapter.last.queryParameters, {'q': 'mi'});
    expect(found.single.followsMe, isTrue);
    await api.rivals();
    expect(adapter.last.path, '/me/rivals');

    adapter.body = {'days': 7, 'taken': 5, 'lost': 1, 'net': 4, 'battles': 2};
    expect((await api.battleSummary()).net, 4);
    adapter.body = {'days': 30, 'rivals': [], 'unattributed': {'taken': 0, 'lost': 0}};
    await api.rivalry(days: 14);
    expect(adapter.last.queryParameters, {'days': 14});
    adapter.body = {'cells': [{'cell': 'a', 'lat': 1.0, 'lng': 2.0, 'boundary': [], 'lost_at': 1, 'lost_to': null}]};
    expect((await api.takeBack()).single.cell, 'a');

    adapter.body = {'items': [], 'next_cursor': null, 'unread_count': 3};
    expect((await api.notifications()).unreadCount, 3);
    adapter.body = {'unread_count': 4};
    expect(await api.unreadCount(), 4);
  });

  test('mark read sends ids or all, never both', () async {
    adapter
      ..status = 204
      ..body = null;
    await api.markRead(ids: ['a', 'b']);
    expect(adapter.last.path, '/notifications/read');
    expect(adapter.last.data, {'ids': ['a', 'b']});
    await api.markRead(all: true);
    expect(adapter.last.data, {'all': true});
  });

  test('a phase 1a error body gives the code and the message', () async {
    adapter
      ..status = 409
      ..body = {'detail': {'code': 'follow_limit', 'message': 'You follow too many'}};
    try {
      await api.follow('u2');
      fail('should throw');
    } on ApiException catch (e) {
      expect(e.statusCode, 409);
      expect(e.code, 'follow_limit');
      expect(e.message, 'You follow too many');
    }
  });

  test('an old style error body (a plain string) still works', () async {
    adapter
      ..status = 404
      ..body = {'detail': 'unknown run'};
    try {
      await api.getRun('x');
      fail('should throw');
    } on ApiException catch (e) {
      expect(e.message, 'unknown run');
      expect(e.code, isNull);
    }
  });

  test('a body of the wrong shape is "malformed", not "offline"', () async {
    adapter.body = ['not', 'an', 'object'];
    await expectLater(
      api.feed(),
      throwsA(isA<ApiException>().having((e) => e.malformed, 'malformed', isTrue)),
    );
  });
}
