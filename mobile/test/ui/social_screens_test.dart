import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:looprun/core/theme.dart';
import 'package:looprun/data/models/api_exception.dart';
import 'package:looprun/data/models/models.dart';
import 'package:looprun/data/models/social_models.dart';
import 'package:looprun/ui/board/board_screen.dart';
import 'package:looprun/data/providers.dart';
import 'package:looprun/ui/core/theme_view_model.dart';
import 'package:looprun/ui/feed/feed_screen.dart';
import 'package:looprun/ui/feed/run_card_view.dart';
import 'package:looprun/ui/feed/run_detail_screen.dart';
import 'package:looprun/ui/inbox/inbox_screen.dart';
import 'package:looprun/ui/inbox/inbox_view_model.dart';
import 'package:looprun/ui/map/map_screen.dart';
import 'package:looprun/ui/people/people_view_models.dart';
import 'package:looprun/ui/people/public_profile_screen.dart';
import 'package:looprun/ui/people/user_list_screen.dart';
import 'package:looprun/ui/people/user_search_screen.dart';
import 'package:looprun/ui/profile/profile_screen.dart';

import '../fakes/social_fixtures.dart';
import 'screen_harness.dart';

/// Pumps [screen] as the home of a small router, with stub pages for the routes the screens open.
Future<ProviderContainer> pumpRouted(WidgetTester tester, Harness h, Widget screen) async {
  usePhoneSize(tester);
  final container = ProviderContainer(overrides: await h.overrides());
  addTearDown(container.dispose);
  await container.read(authRepositoryProvider).restore();
  final router = GoRouter(
    routes: [
      GoRoute(path: '/', builder: (context, state) => Scaffold(body: screen)),
      GoRoute(path: '/home', builder: (context, state) => const Scaffold(body: Text('map page'))),
      GoRoute(
        path: '/board/run/:id',
        builder: (context, state) => Scaffold(body: Text('run page ${state.pathParameters['id']}')),
      ),
      GoRoute(
        path: '/board/user/:id',
        builder: (context, state) => Scaffold(body: Text('user page ${state.pathParameters['id']}')),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: Consumer(
      builder: (context, ref, _) => MaterialApp.router(
        theme: buildTheme(ref.watch(themeViewModelProvider)),
        routerConfig: router,
      ),
    ),
  ));
  await tester.pump();
  return container;
}

Future<void> settleUi(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 30));
  }
}

void main() {
  group('run card', () {
    testWidgets('shows the numbers of the contract and the "took N from X" line', (tester) async {
      final h = Harness();
      final c = card(
        'r1',
        ownerName: 'Bob Marsh',
        claimed: 14,
        taken: 5,
        takenFrom: const [TakenFrom(user: UserRef(id: 'u3', name: 'Cy'), cells: 3)],
        takenHidden: 2,
        kudos: 4,
        comments: 1,
      );
      await pumpScreen(tester, h, RunCardView(card: c, isMine: false, onKudos: () {}, onMenu: (_) {}));
      expect(find.text('BM'), findsOneWidget, reason: 'initials avatar, no photo');
      expect(find.text('Bob Marsh'), findsOneWidget);
      expect(find.text('5.20'), findsOneWidget);
      expect(find.text('27:30'), findsOneWidget);
      expect(find.text('5:17'), findsOneWidget);
      expect(find.textContaining('14 cells claimed'), findsOneWidget);
      expect(find.textContaining('took 3 from Cy and 2 from hidden runners'), findsOneWidget);
      expect(find.text('4'), findsOneWidget);
      expect(find.text('1'), findsOneWidget);
    });

    testWidgets('kudos is a toggle, a 48 dp target with a spoken label', (tester) async {
      final h = Harness();
      var taps = 0;
      final handle = tester.ensureSemantics();
      await pumpScreen(tester, h, RunCardView(card: card('r1', kudos: 2), isMine: false, onKudos: () => taps++));
      final size = tester.getSize(find.byKey(const Key('kudos_button')));
      expect(size.height, greaterThanOrEqualTo(48));
      expect(size.width, greaterThanOrEqualTo(48));
      expect(find.bySemanticsLabel('Give kudos, 2 kudos'), findsOneWidget);
      await tester.tap(find.byKey(const Key('kudos_button')));
      expect(taps, 1);
      handle.dispose();
    });

    testWidgets('a given kudos says "Remove kudos"', (tester) async {
      final h = Harness();
      final handle = tester.ensureSemantics();
      await pumpScreen(tester, h, RunCardView(card: card('r1', kudos: 3, kudosByMe: true), isMine: false, onKudos: () {}));
      expect(find.bySemanticsLabel('Remove kudos, 3 kudos'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('own cards have no kudos button and no report menu', (tester) async {
      final h = Harness();
      await pumpScreen(tester, h, RunCardView(card: card('r1', owner: 'u1', kudos: 2), isMine: true, onMenu: (_) {}));
      expect(find.byKey(const Key('kudos_button')), findsNothing);
      expect(find.byKey(const Key('kudos_count_own')), findsOneWidget);
      expect(find.byKey(const Key('run_card_menu')), findsNothing);
    });

    testWidgets('a run that is processing shows dashes, never zeros', (tester) async {
      final h = Harness();
      await pumpScreen(
        tester,
        h,
        RunCardView(
          card: card('r1', owner: 'u1', status: 'processing', distanceM: null, movingSeconds: null, pace: null, claimed: 0),
          isMine: true,
        ),
      );
      expect(find.text('--'), findsNWidgets(3));
      expect(find.text('Processing'), findsOneWidget);
      expect(find.text('No cells claimed'), findsOneWidget);
    });

    testWidgets('the card menu offers report and block', (tester) async {
      final h = Harness();
      final picked = <RunCardAction>[];
      await pumpScreen(tester, h, RunCardView(card: card('r1'), isMine: false, onMenu: picked.add));
      await tester.tap(find.byKey(const Key('run_card_menu')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('run_card_report')), findsOneWidget);
      expect(find.text('Block Bob'), findsOneWidget);
      await tester.tap(find.byKey(const Key('run_card_report')));
      await tester.pumpAndSettle();
      expect(picked, [RunCardAction.report]);
    });
  });

  group('feed screen', () {
    testWidgets('lists cards and toggles kudos', (tester) async {
      final h = Harness();
      h.api.feedPages = [page([card('r1', kudos: 1), card('r2', ownerName: 'Cy', owner: 'u3')])];
      await pumpScreen(tester, h, const FeedScreen());
      await settleUi(tester);
      expect(find.byKey(const Key('feed_card_r1')), findsOneWidget);
      expect(find.byKey(const Key('feed_card_r2')), findsOneWidget);
      await tester.tap(find.descendant(of: find.byKey(const Key('feed_card_r1')), matching: find.byKey(const Key('kudos_button'))));
      await settleUi(tester);
      expect(h.api.socialCalls, contains('giveKudos:r1'));
    });

    testWidgets('empty feed explains itself and offers search', (tester) async {
      final h = Harness();
      await pumpScreen(tester, h, const FeedScreen());
      await settleUi(tester);
      expect(find.byKey(const Key('list_empty')), findsOneWidget);
      expect(find.byKey(const Key('feed_find_runners')), findsOneWidget);
    });

    testWidgets('offline: a message with "Try again" that works', (tester) async {
      final h = Harness();
      h.api.socialErrors['feed'] = const ApiException(null, 'offline');
      await pumpScreen(tester, h, const FeedScreen());
      await settleUi(tester);
      expect(find.text("Can't reach the server"), findsOneWidget);
      h.api.socialErrors.clear();
      h.api.feedPages = [page([card('r1')])];
      await tester.tap(find.text('Try again'));
      await settleUi(tester);
      expect(find.byKey(const Key('feed_card_r1')), findsOneWidget);
    });

    testWidgets('"Load more" fetches the next page', (tester) async {
      final h = Harness();
      h.api.feedPages = [page([card('r1')], 'p1'), page([card('r2')])];
      await pumpScreen(tester, h, const FeedScreen());
      await settleUi(tester);
      expect(find.byKey(const Key('list_load_more')), findsOneWidget);
      await tester.tap(find.byKey(const Key('list_load_more')));
      await settleUi(tester);
      expect(find.byKey(const Key('feed_card_r2')), findsOneWidget);
    });
  });

  group('board lane', () {
    testWidgets('three parts: ranking, feed, rivals; parts load when first opened', (tester) async {
      final h = Harness();
      h.api.feedPages = [page([card('r1')])];
      h.api.summary = const BattleSummary(taken: 3, lost: 1, net: 2, battles: 1);
      await pumpScreen(tester, h, const BoardScreen());
      await settleUi(tester);
      expect(find.text('THE BOARD'), findsOneWidget);
      expect(h.api.count('feed'), 0, reason: 'the feed is not asked until it is opened');
      await tester.tap(find.byKey(const Key('board_tab_feed')));
      await settleUi(tester);
      expect(find.text('FEED'), findsWidgets);
      expect(find.byKey(const Key('feed_card_r1')), findsOneWidget);
      await tester.tap(find.byKey(const Key('board_tab_rivals')));
      await settleUi(tester);
      expect(find.byKey(const Key('battles_summary')), findsOneWidget);
      expect(find.text('+2'), findsOneWidget);
    });

    testWidgets('rivalry rows and the private group', (tester) async {
      final h = Harness();
      h.api.rivalryResult = const Rivalry(
        rivals: [Rival(user: UserRef(id: 'u2', name: 'Bob'), taken: 5, lost: 2, net: 3, lastBattleAt: 1700000000000)],
        unattributed: BattleCounts(taken: 1, lost: 4),
      );
      await pumpScreen(tester, h, const BoardScreen());
      await tester.tap(find.byKey(const Key('board_tab_rivals')));
      await settleUi(tester);
      expect(find.byKey(const Key('rival_u2')), findsOneWidget);
      expect(find.text('Private runners'), findsOneWidget);
      expect(find.text('You took 1, they took 4'), findsOneWidget);
    });

    testWidgets('the tab buttons are at least 48 dp high', (tester) async {
      final h = Harness();
      await pumpScreen(tester, h, const BoardScreen());
      for (final t in ['ranking', 'feed', 'rivals']) {
        expect(tester.getSize(find.byKey(Key('board_tab_$t'))).height, greaterThanOrEqualTo(48));
      }
      expect(tester.getSize(find.byKey(const Key('find_runners_button'))).height, greaterThanOrEqualTo(48));
    });
  });

  group('public profile', () {
    const bob = Profile(
      id: 'u2',
      name: 'Bob Marsh',
      cellsHeld: 40,
      weeklyRank: 7,
      followersCount: 3,
      followingCount: 4,
      joinedAt: 1700000000000,
      followsMe: true,
    );

    testWidgets('shows the stats and follows / unfollows', (tester) async {
      final h = Harness();
      h.api.profiles['u2'] = bob;
      h.api.followersCountAfterFollow = 4;
      await pumpScreen(tester, h, const PublicProfileScreen(userId: 'u2'));
      await settleUi(tester);
      expect(find.byKey(const Key('profile_name')), findsOneWidget);
      expect(find.text('Bob Marsh'), findsOneWidget);
      expect(find.text('40'), findsOneWidget);
      expect(find.text('#7'), findsOneWidget);
      expect(find.byKey(const Key('follows_you_chip')), findsOneWidget);
      Finder label(String t) => find.descendant(of: find.byKey(const Key('follow_button')), matching: find.text(t));
      expect(label('FOLLOW'), findsOneWidget);
      await tester.tap(find.byKey(const Key('follow_button')));
      await settleUi(tester);
      expect(label('FOLLOWING'), findsOneWidget);
      expect(find.text('4'), findsWidgets, reason: 'followers: the server count');
      await tester.tap(find.byKey(const Key('follow_button')));
      await settleUi(tester);
      expect(label('FOLLOW'), findsOneWidget);
    });

    testWidgets('no rank shows a dash', (tester) async {
      final h = Harness();
      h.api.profiles['u2'] = const Profile(id: 'u2', name: 'Bob');
      await pumpScreen(tester, h, const PublicProfileScreen(userId: 'u2'));
      await settleUi(tester);
      expect(find.descendant(of: find.byKey(const Key('stat_weekly_rank')), matching: find.text('--')), findsOneWidget);
    });

    testWidgets('report: reason, then it reaches the server as kind user', (tester) async {
      final h = Harness();
      h.api.profiles['u2'] = bob;
      await pumpScreen(tester, h, const PublicProfileScreen(userId: 'u2'));
      await settleUi(tester);
      await tester.tap(find.byKey(const Key('profile_menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('profile_report')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('report_reason_field')), 'Rude name');
      await tester.pump();
      await tester.tap(find.byKey(const Key('report_send_button')));
      await settleUi(tester);
      expect(h.api.reports.single, {'kind': 'user', 'target_id': 'u2', 'reason': 'Rude name'});
    });

    testWidgets('block asks first, then blocks', (tester) async {
      final h = Harness();
      h.api.profiles['u2'] = bob;
      await pumpScreen(tester, h, const PublicProfileScreen(userId: 'u2'));
      await settleUi(tester);
      await tester.tap(find.byKey(const Key('profile_menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('profile_block')));
      await tester.pumpAndSettle();
      expect(h.api.blocked, isEmpty, reason: 'nothing before the confirmation');
      await tester.tap(find.byKey(const Key('confirm_block')));
      await settleUi(tester);
      expect(h.api.blocked, ['u2']);
    });

    testWidgets('your own profile has no follow button and no menu', (tester) async {
      final h = Harness();
      h.api.profiles['u1'] = const Profile(id: 'u1', name: 'Vivek', isMe: true);
      await pumpScreen(tester, h, const PublicProfileScreen(userId: 'u1'));
      await settleUi(tester);
      expect(find.byKey(const Key('follow_button')), findsNothing);
      expect(find.byKey(const Key('profile_menu')), findsNothing);
    });

    testWidgets('unknown or blocked: a calm message', (tester) async {
      final h = Harness();
      await pumpScreen(tester, h, const PublicProfileScreen(userId: 'gone'));
      await settleUi(tester);
      expect(find.byKey(const Key('profile_not_found')), findsOneWidget);
    });

    testWidgets('offline: message and retry', (tester) async {
      final h = Harness();
      h.api.profiles['u2'] = bob;
      h.api.socialErrors['getProfile:u2'] = const ApiException(null, 'offline');
      await pumpScreen(tester, h, const PublicProfileScreen(userId: 'u2'));
      await settleUi(tester);
      expect(find.byKey(const Key('profile_error')), findsOneWidget);
      h.api.socialErrors.clear();
      await tester.tap(find.text('Try again'));
      await settleUi(tester);
      expect(find.text('Bob Marsh'), findsOneWidget);
    });
  });

  group('people lists and search', () {
    testWidgets('followers: rows with a follow button that toggles', (tester) async {
      final h = Harness();
      h.api.followerPages = [page([person('a', name: 'Asha', followsMe: true)])];
      await pumpScreen(tester, h, const UserListScreen(kind: PeopleKind.followers));
      await settleUi(tester);
      expect(find.text('Asha'), findsOneWidget);
      expect(find.text('Follows you'), findsOneWidget);
      expect(tester.getSize(find.byKey(const Key('person_action_a'))).height, greaterThanOrEqualTo(48));
      await tester.tap(find.byKey(const Key('person_action_a')));
      await settleUi(tester);
      expect(find.text('FOLLOWING'), findsOneWidget);
    });

    testWidgets('blocked: unblock removes the row; empty list is explained', (tester) async {
      final h = Harness();
      h.api.blockPages = [page([user('u9', 'Zed')])];
      await pumpScreen(tester, h, const UserListScreen(kind: PeopleKind.blocked));
      await settleUi(tester);
      expect(find.text('Zed'), findsOneWidget);
      await tester.tap(find.text('UNBLOCK'));
      await settleUi(tester);
      expect(h.api.unblocked, ['u9']);
      expect(find.text('You have not blocked anyone'), findsOneWidget);
    });

    testWidgets('search: hint, results after typing, "nobody found"', (tester) async {
      final h = Harness();
      h.api.people = [person('a', name: 'Maya'), person('b', name: 'Mark')];
      await pumpScreen(tester, h, const UserSearchScreen());
      await tester.pump();
      expect(find.byKey(const Key('search_hint')), findsOneWidget);
      await tester.enterText(find.byKey(const Key('search_field')), 'ma');
      await tester.pump(const Duration(milliseconds: 500));
      await settleUi(tester);
      expect(find.text('Maya'), findsOneWidget);
      expect(find.text('Mark'), findsOneWidget);
      await tester.enterText(find.byKey(const Key('search_field')), 'zz');
      await tester.pump(const Duration(milliseconds: 500));
      await settleUi(tester);
      expect(find.byKey(const Key('search_empty')), findsOneWidget);
    });
  });

  group('inbox', () {
    test('notification wording', () {
      expect(notificationText(note('1', 'cells_taken', cells: 12)), 'Bob took 12 of your cells');
      expect(notificationText(note('1', 'cells_taken', cells: 1)), 'Bob took 1 of your cells');
      expect(notificationText(note('1', 'cells_taken', cells: 3, unattributed: 4)), 'Bob took 3 of your cells, and hidden runners took 4 more');
      expect(notificationText(note('1', 'cells_taken', actor: null, cells: 0, unattributed: 6)), 'A hidden runner took 6 of your cells');
      expect(notificationText(note('1', 'new_follower')), 'Bob started following you');
      expect(notificationText(note('1', 'kudos')), 'Bob gave kudos on your run');
      expect(notificationText(note('1', 'comment', preview: 'Nice pace')), 'Bob commented: Nice pace');
    });

    testWidgets('lists entries, marks all read, and an entry opens its run and is marked read', (tester) async {
      final h = Harness()..api.unread = 2;
      h.api.notificationPages = [
        page([note('n1', 'kudos', runId: 'r7'), note('n2', 'new_follower'), note('n3', 'comment', read: true, preview: 'hi', runId: 'r7')])
      ];
      final container = await pumpRouted(tester, h, const InboxScreen());
      await settleUi(tester);
      expect(find.text('Bob gave kudos on your run'), findsOneWidget);
      expect(find.text('Bob started following you'), findsOneWidget);
      expect(find.byKey(const Key('unread_dot')), findsNWidgets(2));
      expect(find.byKey(const Key('mark_all_read')), findsOneWidget);

      await tester.tap(find.byKey(const Key('notification_n1')));
      await tester.pumpAndSettle();
      expect(find.text('run page r7'), findsOneWidget, reason: 'opens the run it is about');
      expect(h.api.markedIds, [['n1']]);
      expect(container.read(unreadCountProvider), 1);
    });

    testWidgets('mark all read', (tester) async {
      final h = Harness()..api.unread = 2;
      h.api.notificationPages = [page([note('n1', 'kudos', runId: 'r7'), note('n2', 'new_follower')])];
      await pumpScreen(tester, h, const InboxScreen());
      await settleUi(tester);
      await tester.tap(find.byKey(const Key('mark_all_read')));
      await settleUi(tester);
      expect(h.api.markedAll, 1);
      expect(find.byKey(const Key('unread_dot')), findsNothing);
      expect(find.byKey(const Key('mark_all_read')), findsNothing);
    });

    testWidgets('empty and offline states', (tester) async {
      final h = Harness();
      await pumpScreen(tester, h, const InboxScreen());
      await settleUi(tester);
      expect(find.text('Nothing yet'), findsOneWidget);

      final h2 = Harness();
      h2.api.socialErrors['notifications'] = const ApiException(null, 'offline');
      await pumpScreen(tester, h2, const InboxScreen());
      await settleUi(tester);
      expect(find.text("Can't reach the server"), findsOneWidget);
    });
  });

  group('map header', () {
    testWidgets('the bell shows the unread count and says it aloud', (tester) async {
      final h = Harness()..api.unread = 3;
      final handle = tester.ensureSemantics();
      await pumpScreen(tester, h, const MapScreen());
      await settleUi(tester);
      expect(find.byKey(const Key('inbox_bell')), findsOneWidget);
      expect(find.descendant(of: find.byKey(const Key('inbox_badge')), matching: find.text('3')), findsOneWidget);
      expect(find.bySemanticsLabel('Notifications, 3 unread'), findsOneWidget);
      expect(tester.getSize(find.byKey(const Key('inbox_bell'))).width, greaterThanOrEqualTo(48));
      handle.dispose();
    });

    testWidgets('no badge when nothing is unread, and 99+ when it is a lot', (tester) async {
      final h = Harness();
      await pumpScreen(tester, h, const MapScreen());
      await settleUi(tester);
      expect(find.byKey(const Key('inbox_badge')), findsNothing);

      final h2 = Harness()..api.unread = 140;
      await pumpScreen(tester, h2, const MapScreen());
      await settleUi(tester);
      expect(find.text('99+'), findsOneWidget);
    });

    testWidgets('lost cells: a notice, a sheet with a row per cell, "who" only when public', (tester) async {
      final h = Harness()..api.lostCells = [lost('a', to: user('u2', 'Bob')), lost('b')];
      await pumpScreen(tester, h, const MapScreen());
      await settleUi(tester);
      expect(find.text('2 cells were taken from you'), findsOneWidget);
      await tester.tap(find.byKey(const Key('take_back_notice')));
      await tester.pumpAndSettle();
      expect(find.text('TAKE IT BACK'), findsOneWidget);
      expect(find.text('Taken by Bob'), findsOneWidget);
      expect(find.text('Taken by a private runner'), findsOneWidget);
      expect(tester.getSize(find.byKey(const Key('lost_cell_0'))).height, greaterThanOrEqualTo(48));
      await tester.tap(find.byKey(const Key('take_back_toggle')));
      await tester.pumpAndSettle();
      expect(find.byType(Switch), findsOneWidget);
      expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);
    });

    testWidgets('nothing lost: no notice', (tester) async {
      final h = Harness();
      await pumpScreen(tester, h, const MapScreen());
      await settleUi(tester);
      expect(find.byKey(const Key('take_back_notice')), findsNothing);
    });
  });

  group('you lane', () {
    testWidgets('has the community rows, and the name can be edited', (tester) async {
      final h = Harness();
      await pumpScreen(tester, h, const ProfileScreen());
      await settleUi(tester);
      for (final k in ['edit_name_row', 'history_row', 'followers_row', 'following_row', 'find_runners_row', 'blocked_row']) {
        expect(find.byKey(Key(k)), findsOneWidget, reason: k);
      }
      expect(find.descendant(of: find.byKey(const Key('edit_name_row')), matching: find.text('Vivek')), findsOneWidget);
      await tester.ensureVisible(find.byKey(const Key('edit_name_row')));
      await tester.tap(find.byKey(const Key('edit_name_row')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('rename_field')), '  Mia   K ');
      await tester.tap(find.byKey(const Key('rename_save')));
      await settleUi(tester);
      expect(h.api.renames, ['Mia K']);
      expect(find.text('Name changed.'), findsOneWidget);
    });

    testWidgets('a rejected name is shown in the dialog', (tester) async {
      final h = Harness();
      h.api.socialErrors['renameMe'] = const ApiException(422, 'x', code: 'name_rejected');
      await pumpScreen(tester, h, const ProfileScreen());
      await settleUi(tester);
      await tester.ensureVisible(find.byKey(const Key('edit_name_row')));
      await tester.tap(find.byKey(const Key('edit_name_row')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('rename_field')), 'Some Name');
      await tester.tap(find.byKey(const Key('rename_save')));
      await settleUi(tester);
      expect(find.textContaining('cannot be used'), findsOneWidget);
      expect(find.byKey(const Key('rename_field')), findsOneWidget, reason: 'the dialog stays open');
    });

    testWidgets('a name that is too short never leaves the phone', (tester) async {
      final h = Harness();
      await pumpScreen(tester, h, const ProfileScreen());
      await settleUi(tester);
      await tester.ensureVisible(find.byKey(const Key('edit_name_row')));
      await tester.tap(find.byKey(const Key('edit_name_row')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('rename_field')), 'a');
      await tester.tap(find.byKey(const Key('rename_save')));
      await settleUi(tester);
      expect(find.text('Use at least 2 characters.'), findsOneWidget);
      expect(h.api.renames, isEmpty);
    });
  });

  group('run detail', () {
    testWidgets('comments: list, add, delete own, report and block others', (tester) async {
      final h = Harness();
      h.api.commentPages = [
        page([comment('c1', author: 'u2', authorName: 'Bob', text: 'Great run'), comment('c2', author: 'u1', authorName: 'Vivek', text: 'Thanks', canDelete: true)])
      ];
      await pumpScreen(tester, h, RunDetailScreen(runId: 'r1', card: card('r1', comments: 2)));
      await settleUi(tester);
      expect(find.text('Great run'), findsOneWidget);
      expect(find.text('Thanks'), findsOneWidget);

      // Others' comments can be reported and their author blocked, but not deleted (not the run owner).
      await tester.tap(find.byKey(const Key('comment_menu_c1')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('comment_report')), findsOneWidget);
      expect(find.byKey(const Key('comment_block')), findsOneWidget);
      expect(find.byKey(const Key('comment_delete')), findsNothing);
      await tester.tap(find.byKey(const Key('comment_report')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('report_reason_field')), 'Spam');
      await tester.pump();
      await tester.tap(find.byKey(const Key('report_send_button')));
      await settleUi(tester);
      expect(h.api.reports.single, {'kind': 'comment', 'target_id': 'c1', 'reason': 'Spam'});

      // Own comment: delete (after asking).
      await tester.tap(find.byKey(const Key('comment_menu_c2')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('comment_report')), findsNothing);
      await tester.tap(find.byKey(const Key('comment_delete')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('confirm_delete_comment')));
      await settleUi(tester);
      expect(h.api.deletedComments, ['c2']);
      expect(find.text('Thanks'), findsNothing);

      // Add one.
      await tester.enterText(find.byKey(const Key('comment_field')), 'See you out there');
      await tester.pump();
      await tester.tap(find.byKey(const Key('comment_send')));
      await settleUi(tester);
      expect(h.api.postedComments, ['See you out there']);
      expect(find.text('See you out there'), findsOneWidget);
    });

    testWidgets('the run owner can delete any comment on their run', (tester) async {
      final h = Harness();
      h.api.commentPages = [page([comment('c1', author: 'u2', text: 'Hi', canDelete: true)])];
      await pumpScreen(tester, h, RunDetailScreen(runId: 'r1', card: card('r1', owner: 'u1', ownerName: 'Vivek', comments: 1)));
      await settleUi(tester);
      await tester.tap(find.byKey(const Key('comment_menu_c1')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('comment_delete')), findsOneWidget);
    });

    testWidgets('empty comments, and a send button that waits for text', (tester) async {
      final h = Harness();
      await pumpScreen(tester, h, RunDetailScreen(runId: 'r1', card: card('r1')));
      await settleUi(tester);
      expect(find.byKey(const Key('comments_empty')), findsOneWidget);
      await tester.tap(find.byKey(const Key('comment_send')));
      await settleUi(tester);
      expect(h.api.postedComments, isEmpty);
    });

    testWidgets('a run that is not visible: message and retry', (tester) async {
      final h = Harness();
      h.api.socialErrors['comments:r1'] = const ApiException(404, 'x');
      await pumpScreen(tester, h, const RunDetailScreen(runId: 'r1'));
      await settleUi(tester);
      expect(find.byKey(const Key('comments_error')), findsOneWidget);
      expect(find.text('That is not available any more.'), findsOneWidget);
    });
  });
}
