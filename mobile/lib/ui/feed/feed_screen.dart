import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/routes.dart';
import '../../core/theme.dart';
import '../../data/models/social_models.dart';
import '../auth/auth_view_model.dart';
import '../core/paged_list_view.dart';
import '../core/report_dialog.dart';
import '../core/social_actions_view_model.dart';
import '../core/widgets.dart';
import 'feed_view_model.dart';
import 'run_card_view.dart';

/// Report / block flow for a run card, shared by the feed and the run detail. Returns true when the
/// runner was blocked (their cards are gone from the feed then).
Future<bool> runCardMenuAction(
  BuildContext context,
  WidgetRef ref,
  RunCard card,
  RunCardAction action,
) async {
  final actions = ref.read(socialActionsProvider.notifier);
  if (action == RunCardAction.report) {
    final reason = await askReportReason(context, title: 'Report this run');
    if (reason == null || !context.mounted) return false;
    final out = await actions.report(ReportKind.runCard, card.id, reason);
    tellUser(context, out.error ?? 'Report sent. Thank you.');
    return false;
  }
  final ok = await askConfirm(
    context,
    title: 'Block ${card.user.name}?',
    text: blockExplanation,
    confirmLabel: 'Block',
    confirmKey: const Key('confirm_block'),
    danger: true,
  );
  if (!ok || !context.mounted) return false;
  final out = await actions.block(card.user.id);
  tellUser(context, out.error ?? '${card.user.name} is blocked.');
  return out.ok;
}

/// The FEED part of the BOARD lane: runs of the people you follow and your own, newest first.
class FeedScreen extends ConsumerWidget {
  const FeedScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(feedViewModelProvider);
    final vm = ref.read(feedViewModelProvider.notifier);
    final myId = ref.watch(authViewModelProvider.select((s) => s.user?.id));
    final c = context.lr;
    return PagedListView<RunCard>(
      state: state,
      onRefresh: vm.refresh,
      onLoadMore: vm.loadMore,
      onRetry: vm.retry,
      emptyTitle: 'Nothing here yet',
      emptyText: 'Your runs show up at once. Runs of people you follow show up about half an hour after they finish.',
      emptyAction: LrBox(
        key: const Key('feed_find_runners'),
        onTap: () => context.push(searchPath),
        color: c.raised,
        borderColor: c.line,
        height: 50,
        padding: const EdgeInsets.symmetric(horizontal: 22),
        child: Text('Find runners to follow', style: LrText.body(16, weight: FontWeight.w600, color: c.text)),
      ),
      itemBuilder: (context, card) {
        final mine = card.user.id == myId;
        return RunCardView(
          key: Key('feed_card_${card.id}'),
          card: card,
          isMine: mine,
          onOpen: () => context.push(boardRunPath(card.id), extra: card),
          onComments: () => context.push(boardRunPath(card.id), extra: card),
          onProfile: () => context.push(userProfilePath(card.user.id)),
          onKudos: () async => tellUser(context, await vm.toggleKudos(card)),
          onMenu: (action) async {
            final blocked = await runCardMenuAction(context, ref, card, action);
            if (blocked) await vm.refresh();
          },
        );
      },
    );
  }
}
