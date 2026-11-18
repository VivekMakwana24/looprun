import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/format.dart';
import '../../core/routes.dart';
import '../../core/theme.dart';
import '../../data/models/social_models.dart';
import '../core/lr_page.dart';
import '../core/paged_list_view.dart';
import '../core/widgets.dart';
import 'inbox_view_model.dart';

/// The words of one notification. Pure, so it can be tested without a widget.
String notificationText(AppNotification n) {
  final who = n.actor?.name ?? '';
  switch (n.type) {
    case NotificationType.cellsTaken:
      final named = n.cells ?? 0;
      final hidden = n.cellsUnattributed ?? 0;
      String cells(int k) => k == 1 ? '1 of your cells' : '$k of your cells';
      if (n.actor == null || named == 0) {
        return hidden > 0 ? 'A hidden runner took ${cells(hidden)}' : 'Somebody took some of your cells';
      }
      final base = '$who took ${cells(named)}';
      return hidden > 0 ? '$base, and hidden runners took $hidden more' : base;
    case NotificationType.newFollower:
      return '$who started following you';
    case NotificationType.kudos:
      return '$who gave kudos on your run';
    case NotificationType.comment:
      final preview = n.commentPreview ?? '';
      return preview.isEmpty ? '$who commented on your run' : '$who commented: $preview';
    default:
      return 'Something happened';
  }
}

IconData _iconOf(String type) {
  switch (type) {
    case NotificationType.cellsTaken:
      return Icons.hexagon_outlined;
    case NotificationType.newFollower:
      return Icons.person_add_alt;
    case NotificationType.kudos:
      return Icons.thumb_up_alt_outlined;
    case NotificationType.comment:
      return Icons.chat_bubble_outline;
    default:
      return Icons.notifications_none;
  }
}

/// The notifications inbox: cells taken, new followers, kudos and comments. Tap an entry to open what it
/// is about; it is then marked read. "Mark all read" clears the bell.
class InboxScreen extends ConsumerWidget {
  const InboxScreen({super.key});

  void _open(BuildContext context, AppNotification n) {
    switch (n.type) {
      case NotificationType.cellsTaken:
        // The map lane shows the "take it back" notice; going there is the useful next step.
        context.go(homePath);
        break;
      case NotificationType.newFollower:
        final id = n.actor?.id;
        if (id != null && id.isNotEmpty) context.push(userProfilePath(id));
        break;
      case NotificationType.kudos:
      case NotificationType.comment:
        final run = n.runId;
        if (run != null && run.isNotEmpty) context.push(boardRunPath(run));
        break;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.lr;
    final state = ref.watch(inboxViewModelProvider);
    final vm = ref.read(inboxViewModelProvider.notifier);
    final unread = ref.watch(unreadCountProvider) ?? state.items.where((i) => !i.read).length;
    return LrPage(
      title: 'INBOX',
      actions: [
        if (unread > 0)
          LrBox(
            key: const Key('mark_all_read'),
            onTap: () async {
              final ok = await vm.markAllRead();
              if (!ok && context.mounted) tellUser(context, 'Could not mark them as read. Try again.');
            },
            semanticLabel: 'Mark all notifications read',
            radius: 14,
            height: 48,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text('MARK ALL READ', style: LrText.label(14, color: c.accentText, tracking: 0.1)),
          ),
      ],
      child: PagedListView<AppNotification>(
        state: state,
        onRefresh: vm.refresh,
        onLoadMore: vm.loadMore,
        onRetry: vm.retry,
        emptyTitle: 'Nothing yet',
        emptyText: 'When someone takes your cells, follows you, or reacts to a run, it shows up here.',
        separator: 8,
        itemBuilder: (context, n) => _NotificationRow(
          key: Key('notification_${n.id}'),
          item: n,
          onTap: () {
            vm.markRead(n);
            _open(context, n);
          },
        ),
      ),
    );
  }
}

class _NotificationRow extends StatelessWidget {
  const _NotificationRow({super.key, required this.item, required this.onTap});
  final AppNotification item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.lr;
    final text = notificationText(item);
    final when = formatAgo(DateTime.fromMillisecondsSinceEpoch(item.createdAt));
    return Semantics(
      button: true,
      label: '${item.read ? '' : 'Unread. '}$text, $when',
      excludeSemantics: true,
      child: Material(
        color: item.read ? c.surface : c.raised,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: item.read ? c.line : c.accent),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 64),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
              child: Row(
                children: [
                  Icon(_iconOf(item.type), size: 24, color: item.read ? c.muted : c.accentText),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(text,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: LrText.body(15,
                                weight: item.read ? FontWeight.w400 : FontWeight.w600, color: c.text, height: 1.3)),
                        const SizedBox(height: 2),
                        Text(when, style: LrText.body(12, color: c.muted)),
                      ],
                    ),
                  ),
                  if (!item.read)
                    Container(
                      key: const Key('unread_dot'),
                      width: 10,
                      height: 10,
                      margin: const EdgeInsets.only(left: 8),
                      decoration: BoxDecoration(color: c.accent, shape: BoxShape.circle),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
