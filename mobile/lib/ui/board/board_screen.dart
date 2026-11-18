import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/routes.dart';
import '../../core/theme.dart';
import '../battles/battles_screen.dart';
import '../core/widgets.dart';
import '../feed/feed_screen.dart';
import '../leaderboard/leaderboard_screen.dart';
import 'board_tab_view_model.dart';

/// Lane 2: THE BOARD. Three parts under one title: the ranking (cells held now), the FEED of runs, and the
/// RIVALS (battles). The lane bar keeps its three numbered lanes; see mobile/NOTES.md for why the feed is
/// not a fourth lane.
class BoardScreen extends ConsumerStatefulWidget {
  const BoardScreen({super.key});

  @override
  ConsumerState<BoardScreen> createState() => _BoardScreenState();
}

class _BoardScreenState extends ConsumerState<BoardScreen> {
  /// Parts that were opened at least once stay alive (their lists and scroll positions are kept); a part
  /// nobody opened asks the server for nothing.
  final Set<BoardTab> _visited = {BoardTab.ranking};

  static const Map<BoardTab, String> _labels = {
    BoardTab.ranking: 'RANKING',
    BoardTab.feed: 'FEED',
    BoardTab.rivals: 'RIVALS',
  };

  @override
  Widget build(BuildContext context) {
    final c = context.lr;
    final tab = ref.watch(boardTabViewModelProvider);
    _visited.add(tab);
    final vm = ref.read(boardTabViewModelProvider.notifier);
    final title = tab == BoardTab.ranking ? 'THE BOARD' : (tab == BoardTab.feed ? 'FEED' : 'RIVALS');

    Widget part(BoardTab t) {
      if (!_visited.contains(t)) return const SizedBox.shrink();
      switch (t) {
        case BoardTab.ranking:
          return const LeaderboardScreen(embedded: true);
        case BoardTab.feed:
          return const FeedScreen();
        case BoardTab.rivals:
          return const BattlesScreen();
      }
    }

    final body = IndexedStack(index: tab.index, children: [for (final t in BoardTab.values) part(t)]);

    return SafeArea(
      bottom: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 12, 0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Text(title,
                      key: const Key('board_title'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: LrText.display(54, color: c.text, tracking: 0.01, height: 0.88)),
                ),
                LrIconButton(
                  key: const Key('find_runners_button'),
                  icon: Icons.person_search_outlined,
                  semanticLabel: 'Find runners',
                  onTap: () => context.push(searchPath),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                for (final t in BoardTab.values) ...[
                  if (t != BoardTab.ranking) const SizedBox(width: 8),
                  Expanded(
                    child: _TabPill(
                      key: Key('board_tab_${t.name}'),
                      label: _labels[t]!,
                      selected: t == tab,
                      onTap: () => vm.select(t),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 8),
          Expanded(child: body),
        ],
      ),
    );
  }
}

class _TabPill extends StatelessWidget {
  const _TabPill({super.key, required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.lr;
    return Semantics(
      selected: selected,
      child: LrBox(
        onTap: onTap,
        semanticLabel: '$label${selected ? ', selected' : ''}',
        color: selected ? c.accent : null,
        borderColor: selected ? null : c.line,
        radius: 999,
        height: 48,
        child: Text(label, style: LrText.label(16, color: selected ? c.onAccent : c.text2, tracking: 0.12)),
      ),
    );
  }
}
