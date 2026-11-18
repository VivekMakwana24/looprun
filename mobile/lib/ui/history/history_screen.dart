import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/routes.dart';
import '../../data/models/social_models.dart';
import '../core/lr_page.dart';
import '../core/paged_list_view.dart';
import '../feed/run_card_view.dart';
import 'history_view_model.dart';

/// Lane 3 > Run history: every run of the caller, newest first, with its own full numbers. Runs that are
/// still processing, in review or not counted say so.
class HistoryScreen extends ConsumerWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(historyViewModelProvider);
    final vm = ref.read(historyViewModelProvider.notifier);
    return LrPage(
      title: 'RUN HISTORY',
      child: PagedListView<RunCard>(
        state: state,
        onRefresh: vm.refresh,
        onLoadMore: vm.loadMore,
        onRetry: vm.retry,
        emptyTitle: 'No runs yet',
        emptyText: 'Finish a run and it shows up here.',
        itemBuilder: (context, card) => RunCardView(
          key: Key('history_card_${card.id}'),
          card: card,
          isMine: true,
          onOpen: () => context.push(boardRunPath(card.id), extra: card),
        ),
      ),
    );
  }
}
