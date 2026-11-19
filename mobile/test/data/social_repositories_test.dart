import 'package:flutter_test/flutter_test.dart';
import 'package:looprun/core/app_exception.dart';
import 'package:looprun/data/models/api_exception.dart';
import 'package:looprun/data/models/models.dart';
import 'package:looprun/data/models/social_models.dart';
import 'package:looprun/data/repositories/battle_repository.dart';
import 'package:looprun/data/repositories/feed_repository.dart';
import 'package:looprun/data/repositories/notification_repository.dart';
import 'package:looprun/data/repositories/report_repository.dart';
import 'package:looprun/data/repositories/user_repository.dart';

import '../fakes/fakes.dart';
import '../fakes/social_fixtures.dart';

void main() {
  late FakeApiService api;

  setUp(() => api = FakeApiService());

  group('UserRepository', () {
    late UserRepository repo;
    setUp(() => repo = UserRepository(api: api));

    test('follow and unfollow call the matching endpoint', () async {
      final f = await repo.setFollowing('u2', true);
      expect(f.isFollowing, isTrue);
      final u = await repo.setFollowing('u2', false);
      expect(u.isFollowing, isFalse);
      expect(api.socialCalls, ['follow:u2', 'unfollow:u2']);
    });

    test('search asks nothing under 2 characters and cuts at 30', () async {
      api.people = [person('a', name: 'Maya'), person('b', name: 'Mark'), person('c', name: 'Amy')];
      expect(await repo.search(' m '), isEmpty);
      expect(api.searches, isEmpty, reason: 'the server would answer 422');
      final found = await repo.search('ma');
      expect(found.map((p) => p.name), ['Maya', 'Mark']);
      await repo.search('x' * 40);
      expect(api.searches.last.length, 30);
    });

    test('a display name is trimmed, collapsed and checked before the server is asked', () async {
      final user = await repo.rename('  Mia   K ');
      expect(api.renames, ['Mia K']);
      expect(user.name, 'Mia K');
      for (final bad in ['a', 'x' * 31, '   ', 'ab\u0000cd', 'zero​width', 'tab\u0007x']) {
        await expectLater(repo.rename(bad), throwsA(isA<AppException>()), reason: 'rejects "$bad"');
      }
      expect(api.renames.length, 1, reason: 'nothing bad reached the server');
    });

    test('a name of 30 code points is fine, also with emoji', () {
      expect(UserRepository.checkDisplayName('ab'), 'ab');
      expect(UserRepository.checkDisplayName('${'x' * 29}\u{1F600}').runes.length, 30);
    });

    test('server refusals pass through as ApiException', () async {
      api.socialErrors['follow:u2'] = const ApiException(409, 'x', code: 'follow_limit');
      await expectLater(repo.setFollowing('u2', true), throwsA(isA<ApiException>().having((e) => e.code, 'code', 'follow_limit')));
      api.socialErrors['renameMe'] = const ApiException(422, 'x', code: 'name_rejected');
      await expectLater(repo.rename('Valid Name'), throwsA(isA<ApiException>()));
    });

    test('lists use the cursor', () async {
      api.followerPages = [page([person('a')], 'p1'), page([person('b')])];
      final first = await repo.followers();
      expect(first.nextCursor, 'p1');
      final second = await repo.followers(cursor: first.nextCursor);
      expect(second.items.single.id, 'b');
      expect(second.hasMore, isFalse);
    });

    test('block, unblock and the blocked list', () async {
      api.blockPages = [page([user('u9', 'Zed')])];
      await repo.block('u9');
      await repo.unblock('u9');
      expect(api.blocked, ['u9']);
      expect(api.unblocked, ['u9']);
      expect((await repo.blocks()).items.single.name, 'Zed');
    });
  });

  group('FeedRepository', () {
    late FeedRepository repo;
    setUp(() => repo = FeedRepository(api: api));

    test('feed and history pages', () async {
      api.feedPages = [page([card('r1')], 'p1'), page([card('r2')])];
      api.historyPages = [page([card('h1', status: 'processing')])];
      final f = await repo.feed();
      expect(f.items.single.id, 'r1');
      expect((await repo.feed(cursor: f.nextCursor)).items.single.id, 'r2');
      expect((await repo.history()).items.single.status, 'processing');
    });

    test('kudos is a PUT to give and a DELETE to remove', () async {
      expect((await repo.setKudos('r1', true)).kudosByMe, isTrue);
      expect((await repo.setKudos('r1', false)).kudosByMe, isFalse);
      expect(api.socialCalls, ['giveKudos:r1', 'removeKudos:r1']);
    });

    test('a comment is trimmed and checked before it is sent', () async {
      final c = await repo.addComment('r1', '  Great run!\n ');
      expect(api.postedComments, ['Great run!']);
      expect(c.text, 'Great run!');
      for (final bad in ['', '   ', 'x' * 501, 'a​b']) {
        await expectLater(repo.addComment('r1', bad), throwsA(isA<AppException>()), reason: 'rejects ${bad.length} chars');
      }
      expect(api.postedComments.length, 1);
      await repo.addComment('r1', 'y' * 500);
      expect(api.postedComments.length, 2, reason: '500 characters are allowed');
    });

    test('newlines inside a comment become spaces', () {
      expect(FeedRepository.checkComment('a\nb\tc'), 'a b c');
    });

    test('ownCard looks through the history pages, and gives up after three', () async {
      api.historyPages = [
        page([card('a')], 'p1'),
        page([card('b')], 'p2'),
        page([card('c')], 'p3'),
        page([card('d')]),
      ];
      expect((await repo.ownCard('b'))?.id, 'b');
      expect(await repo.ownCard('d'), isNull, reason: 'the fourth page is not asked for');
      expect(await repo.ownCard('zz'), isNull);
    });

    test('delete goes to the comment id', () async {
      await repo.deleteComment('r1', 'c9');
      expect(api.deletedComments, ['c9']);
    });
  });

  group('BattleRepository', () {
    test('overview asks both numbers', () async {
      api.summary = const BattleSummary(taken: 5, lost: 2, net: 3, battles: 1);
      api.rivalryResult = const Rivalry(rivals: [Rival(user: UserRef(id: 'u2', name: 'Bob'), taken: 5, lost: 2, net: 3)]);
      final o = await BattleRepository(api: api).overview();
      expect(o.summary.net, 3);
      expect(o.rivalry.rivals.single.user.name, 'Bob');
      expect(api.socialCalls, containsAll(['battleSummary', 'rivalry']));
    });

    test('take-back keeps only cells the map can draw', () async {
      api.lostCells = [lost('a'), const LostCell(cell: 'nowhere')];
      final cells = await BattleRepository(api: api).takeBack();
      expect(cells.map((c) => c.cell), ['a']);
    });
  });

  group('NotificationRepository', () {
    late NotificationRepository repo;
    setUp(() => repo = NotificationRepository(api: api));

    test('mark read sends at most 100 ids per request and nothing for none', () async {
      await repo.markRead([]);
      expect(api.markedIds, isEmpty);
      await repo.markRead([for (var i = 0; i < 250; i++) 'n$i']);
      expect(api.markedIds.map((l) => l.length), [100, 100, 50]);
    });

    test('mark all read and the unread count', () async {
      api.unread = 6;
      expect(await repo.unreadCount(), 6);
      await repo.markAllRead();
      expect(api.markedAll, 1);
      expect(await repo.unreadCount(), 0);
    });

    test('pages carry the unread count', () async {
      api.unread = 2;
      api.notificationPages = [page([note('n1', 'kudos')], 'p1'), page([note('n2', 'comment')])];
      final p = await repo.page();
      expect(p.unreadCount, 2);
      expect(p.nextCursor, 'p1');
      expect((await repo.page(cursor: 'p1')).items.single.id, 'n2');
    });
  });

  group('ReportRepository', () {
    test('reports of the new kinds reach the server with the reason', () async {
      final repo = ReportRepository(api: api);
      await repo.submit(kind: ReportKind.user, targetId: 'u2', reason: '  rude  ');
      await repo.submit(kind: ReportKind.comment, targetId: 'c1', reason: 'spam');
      await repo.submit(kind: ReportKind.runCard, targetId: 'r1', reason: 'fake');
      expect(api.reports, [
        {'kind': 'user', 'target_id': 'u2', 'reason': 'rude'},
        {'kind': 'comment', 'target_id': 'c1', 'reason': 'spam'},
        {'kind': 'run_card', 'target_id': 'r1', 'reason': 'fake'},
      ]);
    });

    test('an empty reason is refused and a long one is cut to 500', () async {
      final repo = ReportRepository(api: api);
      await expectLater(repo.submit(kind: 'user', targetId: 'u2', reason: '  '), throwsA(isA<AppException>()));
      await repo.submit(kind: 'user', targetId: 'u2', reason: 'x' * 600);
      expect(api.reports.single['reason']!.length, 500);
    });
  });
}
