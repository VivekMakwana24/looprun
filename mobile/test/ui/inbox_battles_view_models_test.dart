import 'package:flutter_test/flutter_test.dart';
import 'package:looprun/data/models/api_exception.dart';
import 'package:looprun/data/models/models.dart';
import 'package:looprun/data/models/social_models.dart';
import 'package:looprun/ui/battles/battles_view_model.dart';
import 'package:looprun/ui/inbox/inbox_view_model.dart';

import '../fakes/fakes.dart';
import '../fakes/social_fixtures.dart';
import 'screen_harness.dart';

void main() {
  group('unread count (the bell)', () {
    test('is unknown until the server answers, then follows it', () async {
      final h = Harness()..api.unread = 3;
      final c = await signedInContainer(h);
      final sub = c.listen(unreadCountProvider, (_, __) {});
      expect(sub.read(), isNull);
      await settle();
      expect(sub.read(), 3);
      h.api.unread = 5;
      await c.read(unreadCountProvider.notifier).refresh();
      expect(sub.read(), 5);
    });

    test('offline keeps the old number and shows no error', () async {
      final h = Harness()..api.unread = 3;
      final c = await signedInContainer(h);
      final sub = c.listen(unreadCountProvider, (_, __) {});
      await settle();
      h.api.socialErrors['unreadCount'] = const ApiException(null, 'offline');
      await c.read(unreadCountProvider.notifier).refresh();
      expect(sub.read(), 3);
    });
  });

  group('inbox', () {
    test('loads, shows the unread number from the server, pages', () async {
      final h = Harness()..api.unread = 2;
      h.api.notificationPages = [
        page([note('n1', 'kudos', runId: 'r1'), note('n2', 'new_follower', read: true)], 'p1'),
        page([note('n3', 'comment', preview: 'Nice')]),
      ];
      final c = await signedInContainer(h);
      final bell = c.listen(unreadCountProvider, (_, __) {});
      final sub = c.listen(inboxViewModelProvider, (_, __) {});
      await settle();
      expect(sub.read().items.length, 2);
      expect(bell.read(), 2);
      await c.read(inboxViewModelProvider.notifier).loadMore();
      expect(sub.read().items.map((n) => n.id), ['n1', 'n2', 'n3']);
    });

    test('opening one marks it read and lowers the bell by one', () async {
      final h = Harness()..api.unread = 2;
      h.api.notificationPages = [page([note('n1', 'kudos'), note('n2', 'kudos')])];
      final c = await signedInContainer(h);
      final bell = c.listen(unreadCountProvider, (_, __) {});
      final sub = c.listen(inboxViewModelProvider, (_, __) {});
      await settle();
      final vm = c.read(inboxViewModelProvider.notifier);
      await vm.markRead(sub.read().items.first);
      expect(sub.read().items.first.read, isTrue);
      expect(sub.read().items.last.read, isFalse);
      expect(bell.read(), 1);
      expect(h.api.markedIds, [['n1']]);
      await vm.markRead(sub.read().items.first);
      expect(h.api.markedIds.length, 1, reason: 'already read: nothing is sent again');
    });

    test('a failed mark-read puts the entry back', () async {
      final h = Harness()..api.unread = 1;
      h.api.notificationPages = [page([note('n1', 'kudos')])];
      final c = await signedInContainer(h);
      final sub = c.listen(inboxViewModelProvider, (_, __) {});
      c.listen(unreadCountProvider, (_, __) {});
      await settle();
      h.api.socialErrors['markRead'] = const ApiException(null, 'offline');
      await c.read(inboxViewModelProvider.notifier).markRead(sub.read().items.single);
      expect(sub.read().items.single.read, isFalse);
    });

    test('mark all read clears the list and the bell', () async {
      final h = Harness()..api.unread = 2;
      h.api.notificationPages = [page([note('n1', 'kudos'), note('n2', 'comment')])];
      final c = await signedInContainer(h);
      final bell = c.listen(unreadCountProvider, (_, __) {});
      final sub = c.listen(inboxViewModelProvider, (_, __) {});
      await settle();
      expect(await c.read(inboxViewModelProvider.notifier).markAllRead(), isTrue);
      expect(sub.read().items.every((n) => n.read), isTrue);
      expect(bell.read(), 0);
      expect(h.api.markedAll, 1);
    });

    test('an empty inbox is empty, an offline one says so', () async {
      final h = Harness();
      final c = await signedInContainer(h);
      final sub = c.listen(inboxViewModelProvider, (_, __) {});
      await settle();
      expect(sub.read().isEmpty, isTrue);
      h.api.socialErrors['notifications'] = const ApiException(null, 'offline');
      await c.read(inboxViewModelProvider.notifier).refresh();
      expect(sub.read().offline, isTrue);
    });
  });

  group('battles', () {
    test('summary and rivalry load together', () async {
      final h = Harness();
      h.api.summary = const BattleSummary(taken: 9, lost: 4, net: 5, battles: 3);
      h.api.rivalryResult = const Rivalry(
        rivals: [Rival(user: UserRef(id: 'u2', name: 'Bob'), taken: 9, lost: 4, net: 5)],
        unattributed: BattleCounts(taken: 1, lost: 0),
      );
      final c = await signedInContainer(h);
      final sub = c.listen(battlesViewModelProvider, (_, __) {});
      await settle();
      expect(sub.read().overview!.summary.net, 5);
      expect(sub.read().overview!.rivalry.unattributed.taken, 1);
    });

    test('offline: a message, then try again', () async {
      final h = Harness();
      h.api.socialErrors['rivalry'] = const ApiException(null, 'offline');
      final c = await signedInContainer(h);
      final sub = c.listen(battlesViewModelProvider, (_, __) {});
      await settle();
      expect(sub.read().offline, isTrue);
      expect(sub.read().overview, isNull);
      h.api.socialErrors.clear();
      await c.read(battlesViewModelProvider.notifier).refresh();
      expect(sub.read().overview, isNotNull);
      expect(sub.read().error, isNull);
    });
  });

  group('take it back', () {
    test('loads the lost cells; they are drawn only after "show on map"', () async {
      final h = Harness()..api.lostCells = [lost('a', to: user('u2', 'Bob')), lost('b')];
      final c = await signedInContainer(h);
      final sub = c.listen(takeBackViewModelProvider, (_, __) {});
      await settle();
      expect(sub.read().cells.length, 2);
      expect(sub.read().shown, isFalse);
      final vm = c.read(takeBackViewModelProvider.notifier);
      vm.setShown(true);
      expect(sub.read().shown, isTrue);
      expect(sub.read().focus!.cell, 'a', reason: 'the camera goes to the newest one');
      expect(sub.read().focusSeq, 1);
      vm.focusOn(sub.read().cells.last);
      expect(sub.read().focus!.cell, 'b');
      expect(sub.read().focusSeq, 2);
      vm.setShown(false);
      expect(sub.read().shown, isFalse);
    });

    test('nothing lost: nothing to show', () async {
      final h = Harness();
      final c = await signedInContainer(h);
      final sub = c.listen(takeBackViewModelProvider, (_, __) {});
      await settle();
      c.read(takeBackViewModelProvider.notifier).setShown(true);
      expect(sub.read().shown, isFalse);
      expect(sub.read().cells, isEmpty);
    });

    test('a failure is kept for the sheet and does not clear cells already known', () async {
      final h = Harness()..api.lostCells = [lost('a')];
      final c = await signedInContainer(h);
      final sub = c.listen(takeBackViewModelProvider, (_, __) {});
      await settle();
      h.api.socialErrors['takeBack'] = const ApiException(null, 'offline');
      await c.read(takeBackViewModelProvider.notifier).refresh();
      expect(sub.read().offline, isTrue);
      expect(sub.read().cells.length, 1);
    });
  });
}
