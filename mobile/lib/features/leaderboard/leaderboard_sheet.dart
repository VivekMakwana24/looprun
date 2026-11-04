import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../data/models/models.dart';

final weeklyLeaderboardProvider = FutureProvider.autoDispose<Leaderboard>(
  (ref) => ref.watch(apiClientProvider).weeklyLeaderboard(),
);

Future<void> showLeaderboardSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => const LeaderboardSheet(),
  );
}

class LeaderboardSheet extends ConsumerWidget {
  const LeaderboardSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(weeklyLeaderboardProvider);
    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.6,
      child: data.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Could not load the leaderboard.'),
                const SizedBox(height: 8),
                OutlinedButton(
                  onPressed: () => ref.invalidate(weeklyLeaderboardProvider),
                  child: const Text('Try again'),
                ),
              ],
            ),
          ),
        ),
        data: (board) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text('Cells held, week ${board.week}',
                  style: Theme.of(context).textTheme.titleMedium),
            ),
            Expanded(
              child: board.entries.isEmpty
                  ? const Center(child: Text('Nobody has claimed cells this week yet.'))
                  : ListView(
                      children: [
                        for (final e in board.entries)
                          ListTile(
                            leading: CircleAvatar(child: Text('${e.rank}')),
                            title: Text(e.user.name),
                            trailing: Text('${e.cells}'),
                          ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
