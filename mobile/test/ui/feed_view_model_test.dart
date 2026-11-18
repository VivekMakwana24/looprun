import 'package:flutter_test/flutter_test.dart';
import 'package:looprun/data/models/api_exception.dart';
import 'package:looprun/data/models/social_models.dart';
import 'package:looprun/ui/feed/feed_view_model.dart';
import 'package:looprun/ui/feed/run_detail_view_model.dart';
import 'package:looprun/ui/history/history_view_model.dart';

import '../fakes/fakes.dart';
import '../fakes/social_fixtures.dart';
import 'screen_harness.dart';

void main() {
  group('feed', () {
    test('loads the first page, then the next, without duplicates', () async {
      final h = Harness();
      h.api.feedPages = [
        page([card('r1'), card('r2')], 'p1'),
        page([card('r2'), card('r3')]),
      ];
      final c = await signedInContainer(h);
      final sub = c.listen(feedViewModelProvider, (_, __) {});
      expect(sub.read().loading, isTrue);
      await settle();
      expect(sub.read().items.map((i) => i.id), ['r1', 'r2']);
      expect(sub.read().hasMore, isTrue);

      await c.read(feedViewModelProvider.notifier).loadMore();
      expect(sub.read().items.map((i) => i.id), ['r1', 'r2', 'r3'], reason: 'the overlapping card is shown once');
      expect(sub.read().hasMore, isFalse);
      await c.read(feedViewModelProvider.notifier).loadMore();
      expect(h.api.count('feed'), 2, reason: 'no request after the last page');
    });

    test('an empty feed is "empty", not an error', () async {
      final h = Harness();
      final c = await signedInContainer(h);
      final sub = c.listen(feedViewModelProvider, (_, __) {});
      await settle();
      expect(sub.read().isEmpty, isTrue);
      expect(sub.read().error, isNull);
    });

    test('offline: a message, and "try again" loads it', () async {
      final h = Harness();
      h.api.socialErrors['feed'] = const ApiException(null, 'offline');
      h.api.feedPages = [page([card('r1')])];
      final c = await signedInContainer(h);
      final sub = c.listen(feedViewModelProvider, (_, __) {});
      await settle();
      expect(sub.read().offline, isTrue);
      expect(sub.read().error, contains('connection'));
      expect(sub.read().items, isEmpty);

      h.api.socialErrors.clear();
      await c.read(feedViewModelProvider.notifier).retry();
      expect(sub.read().error, isNull);
      expect(sub.read().items.single.id, 'r1');
    });

    test('a failed refresh keeps the cards that were shown', () async {
      final h = Harness();
      h.api.feedPages = [page([card('r1')])];
      final c = await signedInContainer(h);
      final sub = c.listen(feedViewModelProvider, (_, __) {});
      await settle();
      h.api.socialErrors['feed'] = const ApiException(null, 'offline');
      await c.read(feedViewModelProvider.notifier).refresh();
      expect(sub.read().items.single.id, 'r1');
      expect(sub.read().offline, isTrue);
    });

    test('kudos changes the card at once and keeps the server numbers', () async {
      final h = Harness();
      h.api.feedPages = [page([card('r1', kudos: 2)])];
      h.api.kudosAfterGive = const KudosState(kudosByMe: true, kudosCount: 5);
      final c = await signedInContainer(h);
      final sub = c.listen(feedViewModelProvider, (_, __) {});
      await settle();
      final vm = c.read(feedViewModelProvider.notifier);
      final pending = vm.toggleKudos(sub.read().items.single);
      expect(sub.read().items.single.kudosByMe, isTrue, reason: 'optimistic');
      expect(sub.read().items.single.kudosCount, 3);
      expect(await pending, isNull);
      expect(sub.read().items.single.kudosCount, 5, reason: 'the server count wins');
      expect(h.api.socialCalls, contains('giveKudos:r1'));

      await vm.toggleKudos(sub.read().items.single);
      expect(h.api.socialCalls, contains('removeKudos:r1'));
      expect(sub.read().items.single.kudosByMe, isFalse);
    });

    test('a refused kudos goes back and says why', () async {
      final h = Harness();
      h.api.feedPages = [page([card('r1', kudos: 2)])];
      h.api.socialErrors['giveKudos:r1'] = const ApiException(404, 'x');
      final c = await signedInContainer(h);
      final sub = c.listen(feedViewModelProvider, (_, __) {});
      await settle();
      final error = await c.read(feedViewModelProvider.notifier).toggleKudos(sub.read().items.single);
      expect(error, contains('not available'));
      expect(sub.read().items.single.kudosByMe, isFalse);
      expect(sub.read().items.single.kudosCount, 2);
    });

    test('a second tap while the first is on its way is ignored', () async {
      final h = Harness();
      h.api.feedPages = [page([card('r1')])];
      final c = await signedInContainer(h);
      final sub = c.listen(feedViewModelProvider, (_, __) {});
      await settle();
      final vm = c.read(feedViewModelProvider.notifier);
      final item = sub.read().items.single;
      final a = vm.toggleKudos(item);
      final b = vm.toggleKudos(item);
      await Future.wait([a, b]);
      expect(h.api.count('giveKudos'), 1);
    });
  });

  group('history', () {
    test('lists own runs including the ones still processing', () async {
      final h = Harness();
      h.api.historyPages = [
        page([card('r1', owner: 'u1', status: 'processing', distanceM: null, movingSeconds: null, pace: null, claimed: 0)])
      ];
      final c = await signedInContainer(h);
      final sub = c.listen(historyViewModelProvider, (_, __) {});
      await settle();
      expect(sub.read().items.single.isProcessing, isTrue);
      expect(sub.read().items.single.distanceM, isNull);
    });
  });

  group('run detail', () {
    RunDetailArgs args([RunCard? card]) => RunDetailArgs('r1', card);

    test('shows the card at once and loads the comments', () async {
      final h = Harness();
      h.api.commentPages = [page([comment('c1'), comment('c2')])];
      final c = await signedInContainer(h);
      final p = runDetailViewModelProvider(args(card('r1', comments: 2)));
      final sub = c.listen(p, (_, __) {});
      expect(sub.read().card!.commentCount, 2);
      expect(sub.read().loaded, isFalse);
      await settle();
      expect(sub.read().comments.map((e) => e.id), ['c1', 'c2']);
      expect(sub.read().loaded, isTrue);
    });

    test('add a comment: it appears, the count goes up, the feed card follows', () async {
      final h = Harness();
      h.api.feedPages = [page([card('r1', comments: 1)])];
      final c = await signedInContainer(h);
      final feed = c.listen(feedViewModelProvider, (_, __) {});
      await settle();
      final p = runDetailViewModelProvider(args(feed.read().items.single));
      final sub = c.listen(p, (_, __) {});
      await settle();

      final error = await c.read(p.notifier).post('  Nice one ');
      expect(error, isNull);
      expect(sub.read().comments.single.text, 'Nice one');
      expect(sub.read().card!.commentCount, 2);
      expect(feed.read().items.single.commentCount, 2);
    });

    test('a bad comment is refused with a sentence and nothing is sent', () async {
      final h = Harness();
      final c = await signedInContainer(h);
      final p = runDetailViewModelProvider(args(card('r1')));
      c.listen(p, (_, __) {});
      await settle();
      expect(await c.read(p.notifier).post('   '), isNotNull);
      expect(await c.read(p.notifier).post('x' * 501), contains('500'));
      expect(h.api.postedComments, isEmpty);
    });

    test('server limit is explained', () async {
      final h = Harness();
      h.api.socialErrors['addComment:r1'] = const ApiException(409, 'x', code: 'comment_limit');
      final c = await signedInContainer(h);
      final p = runDetailViewModelProvider(args(card('r1')));
      final sub = c.listen(p, (_, __) {});
      await settle();
      expect(await c.read(p.notifier).post('hello'), contains('200'));
      expect(sub.read().posting, isFalse);
      expect(sub.read().comments, isEmpty);
    });

    test('delete removes the comment and lowers the count', () async {
      final h = Harness();
      h.api.commentPages = [page([comment('c1', canDelete: true), comment('c2')])];
      final c = await signedInContainer(h);
      final p = runDetailViewModelProvider(args(card('r1', comments: 2)));
      final sub = c.listen(p, (_, __) {});
      await settle();
      expect(await c.read(p.notifier).deleteComment(sub.read().comments.first), isNull);
      expect(sub.read().comments.map((e) => e.id), ['c2']);
      expect(sub.read().card!.commentCount, 1);
      expect(h.api.deletedComments, ['c1']);
    });

    test('blocking an author drops their comments from the list', () async {
      final h = Harness();
      h.api.commentPages = [page([comment('c1', author: 'u2'), comment('c2', author: 'u3')])];
      final c = await signedInContainer(h);
      final p = runDetailViewModelProvider(args(card('r1')));
      final sub = c.listen(p, (_, __) {});
      await settle();
      c.read(p.notifier).removeCommentsOf('u2');
      expect(sub.read().comments.map((e) => e.id), ['c2']);
    });

    test('a run that is not visible says so and "try again" works', () async {
      final h = Harness();
      h.api.socialErrors['comments:r1'] = const ApiException(404, 'x');
      final c = await signedInContainer(h);
      final p = runDetailViewModelProvider(args());
      final sub = c.listen(p, (_, __) {});
      await settle();
      expect(sub.read().error, contains('not available'));
      expect(sub.read().loaded, isFalse);
      h.api.socialErrors.clear();
      h.api.commentPages = [page([comment('c1')])];
      await c.read(p.notifier).refresh();
      expect(sub.read().comments.single.id, 'c1');
    });

    test('kudos on the detail card', () async {
      final h = Harness();
      final c = await signedInContainer(h);
      final p = runDetailViewModelProvider(args(card('r1', kudos: 0)));
      final sub = c.listen(p, (_, __) {});
      await settle();
      expect(await c.read(p.notifier).toggleKudos(), isNull);
      expect(sub.read().card!.kudosByMe, isTrue);
      expect(sub.read().card!.kudosCount, 1);
    });

    test('more comments are loaded page by page', () async {
      final h = Harness();
      h.api.commentPages = [page([comment('c1')], 'p1'), page([comment('c2')])];
      final c = await signedInContainer(h);
      final p = runDetailViewModelProvider(args(card('r1')));
      final sub = c.listen(p, (_, __) {});
      await settle();
      expect(sub.read().hasMore, isTrue);
      await c.read(p.notifier).loadMore();
      expect(sub.read().comments.map((e) => e.id), ['c1', 'c2']);
      expect(sub.read().hasMore, isFalse);
    });
  });
}
