import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../data/models/api_exception.dart';
import '../auth/auth_view_model.dart';
import '../core/widgets.dart';
import 'leaderboard_view_model.dart';

/// Lane 2: THE BOARD, cells held this week.
class LeaderboardScreen extends ConsumerWidget {
  const LeaderboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.lr;
    final data = ref.watch(weeklyLeaderboardProvider);
    final myId = ref.watch(authViewModelProvider.select((s) => s.user?.id));
    final board = data.valueOrNull;
    final week = board == null ? null : formatWeekLabel(board.week);
    final offline = data.hasError && data.error is ApiException && (data.error as ApiException).isNetwork;

    Widget body;
    if (board == null && data.isLoading) {
      body = Padding(
        padding: const EdgeInsets.symmetric(vertical: 48),
        child: Center(child: CircularProgressIndicator(color: c.accent)),
      );
    } else if (board == null) {
      body = _pad(LrMessage(
        key: const Key('board_error'),
        title: offline ? "Can't reach the server" : 'The board could not be loaded',
        text: offline ? 'Check your connection.' : null,
        actionLabel: 'Try again',
        onAction: () => ref.invalidate(weeklyLeaderboardProvider),
      ));
    } else {
      final view = buildBoardView(board, myUserId: myId);
      final laneUp = view.laneUp;
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (laneUp != null) ...[
            _pad(LrCard(
              key: const Key('lane_up_card'),
              radius: 20,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  Text('${laneUp.cellsNeeded}',
                      style: LrText.display(46, color: c.accentText, height: 0.9)),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(laneUp.cellsNeeded == 1 ? 'cell to move up a lane' : 'cells to move up a lane',
                            style: LrText.body(15, weight: FontWeight.w600, color: c.text)),
                        const SizedBox(height: 2),
                        Text('${laneUp.holderName} holds lane ${laneUp.holderLane} with ${laneUp.holderCells}',
                            style: LrText.body(13, color: c.muted)),
                      ],
                    ),
                  ),
                ],
              ),
            )),
            const SizedBox(height: 14),
          ],
          if (view.rows.isEmpty)
            _pad(const LrMessage(
              key: Key('board_empty'),
              title: 'Nobody holds cells this week yet',
              text: 'Run a closed loop and take lane 1.',
            ))
          else
            Column(
              children: [
                Column(
                children: [
                  for (var i = 0; i < view.rows.length; i++) ...[
                    if (view.myRowBelowList && i == view.rows.length - 1) const _Gap(),
                    _LaneRow(row: view.rows[i]),
                  ],
                ],
                ),
                Container(
                  height: 1,
                  margin: const EdgeInsets.symmetric(horizontal: 20),
                  color: c.line,
                ),
              ],
            ),
          const SizedBox(height: 14),
          _pad(Text('Counts cells that are already public. Your own cells count at once.',
              style: LrText.body(13, color: c.muted, height: 1.4))),
        ],
      );
    }

    return SafeArea(
      bottom: false,
      child: RefreshIndicator(
        color: c.accent,
        backgroundColor: c.surface,
        onRefresh: () async {
          ref.invalidate(weeklyLeaderboardProvider);
          try {
            await ref.read(weeklyLeaderboardProvider.future);
          } catch (_) {}
        },
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.only(top: 22, bottom: 20),
          child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _pad(Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Text('THE BOARD', style: LrText.display(60, color: c.text, tracking: 0.01, height: 0.88)),
                ),
                if (week != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(week, style: LrText.label(14, color: c.accentText)),
                        const SizedBox(height: 2),
                        Text('Resets Monday', style: LrText.body(13, color: c.muted)),
                      ],
                    ),
                  ),
              ],
            )),
            const SizedBox(height: 14),
            if (offline && board != null) ...[_pad(const OfflineBanner()), const SizedBox(height: 14)],
            body,
          ],
        ),
        ),
      ),
    );
  }
}

Widget _pad(Widget child) => Padding(padding: const EdgeInsets.symmetric(horizontal: 20), child: child);

/// "..." between the listed lanes and the caller's own lane further down.
class _Gap extends StatelessWidget {
  const _Gap();

  @override
  Widget build(BuildContext context) {
    final c = context.lr;
    return Container(
      height: 32,
      margin: const EdgeInsets.symmetric(horizontal: 20),
      alignment: Alignment.center,
      decoration: BoxDecoration(border: Border(top: BorderSide(color: c.line))),
      child: Text('...', style: LrText.display(20, color: c.muted, height: 1)),
    );
  }
}

class _LaneRow extends StatelessWidget {
  const _LaneRow({required this.row});
  final BoardRow row;

  @override
  Widget build(BuildContext context) {
    final c = context.lr;
    final me = row.isMe;
    final barHeight = me ? 8.0 : 6.0;
    final rank = row.rank == null ? noValue : '${row.rank}';
    final content = Row(
      children: [
        SizedBox(
          width: 34,
          child: Text(rank,
              style: LrText.display(me ? 34 : 30, color: me ? c.accentText : c.muted, height: 1),
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.visible),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Expanded(
                    child: Text(row.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: LrText.body(me ? 17 : 16, weight: FontWeight.w600, color: c.text)),
                  ),
                  Text('${row.cells}',
                      style: LrText.display(me ? 28 : 24, color: me ? c.accentText : c.text, height: 1)),
                ],
              ),
              const SizedBox(height: 7),
              ClipRRect(
                borderRadius: BorderRadius.circular(barHeight / 2),
                child: SizedBox(
                  height: barHeight,
                  child: Stack(
                    children: [
                      Positioned.fill(child: ColoredBox(color: c.line)),
                      FractionallySizedBox(
                        widthFactor: row.fraction,
                        heightFactor: 1,
                        child: ColoredBox(color: me ? c.accent : c.muted),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
    return Semantics(
      label: '${row.rank == null ? '' : 'Lane ${row.rank}, '}${row.name}, ${row.cells} cells',
      selected: me,
      excludeSemantics: true,
      child: Container(
        key: me ? const Key('board_my_row') : null,
        height: me ? 64 : 57,
        // The rows sit in the full-width list; ordinary rows keep the 20 px gutter, the caller's row
        // is highlighted edge to edge.
        margin: me ? EdgeInsets.zero : const EdgeInsets.symmetric(horizontal: 20),
        padding: me ? const EdgeInsets.symmetric(horizontal: 20) : EdgeInsets.zero,
        decoration: BoxDecoration(
          color: me ? c.raised : null,
          border: Border(top: BorderSide(color: c.line)),
        ),
        child: content,
      ),
    );
  }
}
