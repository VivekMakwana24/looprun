import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/models.dart';
import '../../data/providers.dart';
import '../auth/auth_view_model.dart';

/// The weekly board from the server. Also feeds "cells held" and "rank this week" on the map and in Profile.
final weeklyLeaderboardProvider = FutureProvider.autoDispose<Leaderboard>((ref) {
  // Per account: load again when somebody else signs in.
  ref.watch(authViewModelProvider.select((s) => s.user?.id));
  return ref.watch(cellRepositoryProvider).weeklyLeaderboard();
});

/// One lane (row) of the board.
class BoardRow {
  const BoardRow({
    required this.rank,
    required this.name,
    required this.cells,
    required this.fraction,
    this.isMe = false,
  });

  /// Null for the caller's own row when the server gave no rank.
  final int? rank;
  final String name;
  final int cells;

  /// 0..1: this row's cells relative to the leader's, for the bar.
  final double fraction;
  final bool isMe;
}

/// "N cells to move up a lane".
class LaneUp {
  const LaneUp({
    required this.cellsNeeded,
    required this.holderName,
    required this.holderLane,
    required this.holderCells,
  });
  final int cellsNeeded;
  final String holderName;
  final int holderLane;
  final int holderCells;
}

/// What the board screen draws, worked out from the server's answer.
class BoardView {
  const BoardView({required this.rows, this.myRowBelowList = false, this.laneUp});

  final List<BoardRow> rows;

  /// True when the caller's row is not among the listed entries and was added at the end.
  final bool myRowBelowList;

  /// Null when it cannot be worked out (the caller leads, holds nothing, or the runner one lane up is
  /// not in the list).
  final LaneUp? laneUp;
}

BoardView buildBoardView(Leaderboard board, {String? myUserId}) {
  final entries = board.entries;
  var top = 0;
  for (final e in entries) {
    if (e.cells > top) top = e.cells;
  }
  final me = board.me;
  if (me != null && me.cells > top) top = me.cells;
  double frac(int cells) => top <= 0 ? 0 : (cells / top).clamp(0.0, 1.0).toDouble();

  final rows = <BoardRow>[];
  var meListed = false;
  for (final e in entries) {
    final isMe = myUserId != null && myUserId.isNotEmpty && e.user.id == myUserId;
    if (isMe) meListed = true;
    rows.add(BoardRow(
      rank: e.rank,
      name: isMe ? 'You' : (e.user.name.isEmpty ? 'Runner' : e.user.name),
      cells: e.cells,
      fraction: frac(e.cells),
      isMe: isMe,
    ));
  }
  var below = false;
  if (!meListed && me != null && me.rank != null) {
    rows.add(BoardRow(rank: me.rank, name: 'You', cells: me.cells, fraction: frac(me.cells), isMe: true));
    below = true;
  }

  LaneUp? laneUp;
  final myRank = me?.rank;
  if (me != null && myRank != null && myRank > 1) {
    for (final e in entries) {
      if (e.rank == myRank - 1) {
        final diff = e.cells - me.cells;
        laneUp = LaneUp(
          cellsNeeded: diff < 1 ? 1 : diff,
          holderName: e.user.name.isEmpty ? 'A runner' : e.user.name,
          holderLane: e.rank,
          holderCells: e.cells,
        );
        break;
      }
    }
  }
  return BoardView(rows: rows, myRowBelowList: below, laneUp: laneUp);
}

/// The two numbers shown at the top of the map and in Profile.
class MyStanding {
  const MyStanding({this.cells, this.rank, this.week});

  /// Cells the caller holds this week (as the board counts them); null while unknown.
  final int? cells;

  /// Null while unknown or when the caller holds no cells.
  final int? rank;

  /// The server's ISO week ("2026-W47"), or null while unknown.
  final String? week;
}

/// Loading or failed: everything null (the screens then show a dash, never a made-up number).
final myStandingProvider = Provider.autoDispose<MyStanding>((ref) {
  final board = ref.watch(weeklyLeaderboardProvider).valueOrNull;
  if (board == null) return const MyStanding();
  final me = board.me;
  return MyStanding(cells: me?.cells, rank: me?.rank, week: board.week.isEmpty ? null : board.week);
});
