import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:looprun/data/models/api_exception.dart';
import 'package:looprun/data/models/models.dart';
import 'package:looprun/data/providers.dart';
import 'package:looprun/data/services/token_store.dart';
import 'package:looprun/ui/leaderboard/leaderboard_view_model.dart';

import '../fakes/fakes.dart';

LeaderboardEntry entry(int rank, String id, String name, int cells) =>
    LeaderboardEntry(rank: rank, user: UserRef(id: id, name: name), cells: cells);

void main() {
  final sample = Leaderboard(
    week: '2026-W47',
    entries: [
      entry(1, 'a', 'Asha', 212),
      entry(2, 'r', 'Rohan', 187),
      entry(3, 'm', 'Meera', 141),
      entry(4, 'u1', 'Vivek', 128),
      entry(5, 'k', 'Kabir', 96),
    ],
    me: const LeaderboardMe(rank: 4, cells: 128),
  );

  group('buildBoardView', () {
    test('rows keep the server order, bars are relative to the leader, my row says You', () {
      final view = buildBoardView(sample, myUserId: 'u1');
      expect(view.rows.map((r) => r.name), ['Asha', 'Rohan', 'Meera', 'You', 'Kabir']);
      expect(view.rows[0].fraction, 1.0);
      expect(view.rows[1].fraction, closeTo(187 / 212, 1e-9));
      expect(view.rows[3].isMe, isTrue);
      expect(view.rows.where((r) => r.isMe).length, 1);
      expect(view.myRowBelowList, isFalse);
    });

    test('cells to move up a lane come from the runner one lane above', () {
      final up = buildBoardView(sample, myUserId: 'u1').laneUp!;
      expect(up.cellsNeeded, 13);
      expect(up.holderName, 'Meera');
      expect(up.holderLane, 3);
      expect(up.holderCells, 141);
    });

    test('no lane-up card for the leader, for a runner without cells, or without my place', () {
      final leader = Leaderboard(
        week: 'w',
        entries: [entry(1, 'u1', 'Vivek', 9)],
        me: const LeaderboardMe(rank: 1, cells: 9),
      );
      expect(buildBoardView(leader, myUserId: 'u1').laneUp, isNull);

      final nothing = Leaderboard(
        week: 'w',
        entries: [entry(1, 'a', 'Asha', 9)],
        me: const LeaderboardMe(rank: null, cells: 0),
      );
      final view = buildBoardView(nothing, myUserId: 'u1');
      expect(view.laneUp, isNull);
      expect(view.rows.any((r) => r.isMe), isFalse, reason: 'no invented row for a runner with no cells');

      final oldServer = Leaderboard(week: 'w', entries: [entry(1, 'a', 'Asha', 9)]);
      expect(buildBoardView(oldServer, myUserId: 'u1').laneUp, isNull);
    });

    test('a place below the listed entries is added as my row; no card when the lane above is not listed', () {
      final board = Leaderboard(
        week: 'w',
        entries: [entry(1, 'a', 'Asha', 50), entry(2, 'b', 'Bo', 40)],
        me: const LeaderboardMe(rank: 37, cells: 3),
      );
      final view = buildBoardView(board, myUserId: 'u1');
      expect(view.myRowBelowList, isTrue);
      expect(view.rows.last.isMe, isTrue);
      expect(view.rows.last.rank, 37);
      expect(view.rows.last.cells, 3);
      expect(view.laneUp, isNull);
    });

    test('a tie with the lane above still needs one more cell', () {
      final board = Leaderboard(
        week: 'w',
        entries: [entry(1, 'a', 'Asha', 5), entry(2, 'u1', 'Vivek', 5)],
        me: const LeaderboardMe(rank: 2, cells: 5),
      );
      expect(buildBoardView(board, myUserId: 'u1').laneUp!.cellsNeeded, 1);
    });

    test('an empty board gives no rows and no bars above zero', () {
      final view = buildBoardView(const Leaderboard(week: 'w', entries: []), myUserId: 'u1');
      expect(view.rows, isEmpty);
      expect(view.laneUp, isNull);
    });
  });

  group('myStandingProvider', () {
    ProviderContainer make(FakeApiService api) => ProviderContainer(overrides: [
          apiServiceProvider.overrideWithValue(api),
          liveServiceProvider.overrideWithValue(FakeLiveService()),
          tokenStoreProvider.overrideWithValue(
            InMemoryTokenStore(const StoredSession(token: 't', userId: 'u1', userName: 'Vivek')),
          ),
          googleAuthServiceProvider.overrideWithValue(FakeGoogleAuthService()),
        ]);

    test('is empty while loading, then carries my cells, rank and the week', () async {
      final api = FakeApiService()..board = sample;
      final c = make(api);
      addTearDown(c.dispose);
      final sub = c.listen(myStandingProvider, (previous, next) {});
      expect(sub.read().cells, isNull);
      expect(sub.read().rank, isNull);
      await settle();
      expect(sub.read().cells, 128);
      expect(sub.read().rank, 4);
      expect(sub.read().week, '2026-W47');
    });

    test('stays empty (no invented numbers) when the board cannot be loaded', () async {
      final api = FakeApiService()..boardError = const ApiException(null, 'offline');
      final c = make(api);
      addTearDown(c.dispose);
      final sub = c.listen(myStandingProvider, (previous, next) {});
      await settle();
      expect(sub.read().cells, isNull);
      expect(sub.read().rank, isNull);
      expect(sub.read().week, isNull);
    });
  });
}
