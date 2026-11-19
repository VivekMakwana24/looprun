import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/routes.dart';
import '../../core/theme.dart';
import '../../data/models/social_models.dart';
import '../core/initials_avatar.dart';
import '../core/lr_page.dart';
import '../core/paged_list_view.dart';
import '../core/report_dialog.dart';
import '../core/social_actions_view_model.dart';
import '../core/widgets.dart';
import 'people_view_models.dart';

/// One row of a list of people: avatar, name, "Follows you", and one button (follow / following / unblock).
class PersonRow extends StatelessWidget {
  const PersonRow({
    super.key,
    required this.person,
    required this.actionLabel,
    required this.onAction,
    this.onOpen,
    this.onReport,
    this.actionFilled = false,
  });

  final UserListItem person;
  final String? actionLabel;
  final VoidCallback? onAction;
  final VoidCallback? onOpen;

  /// Offers "Report" next to the button (the blocked list: reporting stays possible after a block).
  final VoidCallback? onReport;

  /// The button is the call to action (Follow), not a status (Following).
  final bool actionFilled;

  @override
  Widget build(BuildContext context) {
    final c = context.lr;
    return LrCard(
      radius: 18,
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              onTap: onOpen,
              borderRadius: BorderRadius.circular(18),
              child: Semantics(
                button: onOpen != null,
                label: person.followsMe ? '${person.name}, follows you' : person.name,
                excludeSemantics: true,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 64),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
                    child: Row(
                      children: [
                        InitialsAvatar(name: person.name, size: 40),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(person.name.isEmpty ? 'Runner' : person.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: LrText.body(16, weight: FontWeight.w600, color: c.text)),
                              if (person.followsMe)
                                Text('Follows you', style: LrText.body(13, color: c.muted)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (onReport != null)
            LrIconButton(
              key: Key('person_report_${person.id}'),
              icon: Icons.flag_outlined,
              semanticLabel: 'Report ${person.name}',
              onTap: onReport,
            ),
          if (actionLabel != null)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: LrBox(
                key: Key('person_action_${person.id}'),
                onTap: onAction,
                semanticLabel: '$actionLabel ${person.name}',
                color: actionFilled ? c.accent : null,
                borderColor: actionFilled ? null : c.line,
                radius: 14,
                height: 44,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Text(actionLabel!,
                    style: LrText.label(15, color: actionFilled ? c.onAccent : c.text, tracking: 0.1)),
              ),
            ),
        ],
      ),
    );
  }
}

String _titleOf(PeopleKind k) {
  switch (k) {
    case PeopleKind.followers:
      return 'FOLLOWERS';
    case PeopleKind.following:
      return 'FOLLOWING';
    case PeopleKind.blocked:
      return 'BLOCKED';
    case PeopleKind.rivals:
      return 'RIVALS';
  }
}

String _emptyTitle(PeopleKind k) {
  switch (k) {
    case PeopleKind.followers:
      return 'No followers yet';
    case PeopleKind.following:
      return 'You are not following anyone';
    case PeopleKind.blocked:
      return 'You have not blocked anyone';
    case PeopleKind.rivals:
      return 'No rivals yet';
  }
}

String _emptyText(PeopleKind k) {
  switch (k) {
    case PeopleKind.followers:
      return 'People who follow you show up here.';
    case PeopleKind.following:
      return 'Search for a runner and follow them to see their runs in your feed.';
    case PeopleKind.blocked:
      return 'People you block can be unblocked here.';
    case PeopleKind.rivals:
      return 'Runners you trade cells with in the next 30 days show up here.';
  }
}

/// Followers, following, blocked users, or rivals: the same list with a different data source.
class UserListScreen extends ConsumerWidget {
  const UserListScreen({super.key, required this.kind});
  final PeopleKind kind;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = peopleProviderFor(kind);
    final state = ref.watch(provider);
    final vm = ref.read(provider.notifier);
    final blocked = kind == PeopleKind.blocked;
    return LrPage(
      title: _titleOf(kind),
      child: PagedListView<UserListItem>(
        state: state,
        onRefresh: vm.refresh,
        onLoadMore: vm.loadMore,
        onRetry: vm.retry,
        emptyTitle: _emptyTitle(kind),
        emptyText: _emptyText(kind),
        separator: 10,
        itemBuilder: (context, person) => PersonRow(
          key: Key('person_${person.id}'),
          person: person,
          // A blocked profile is a 404, so those rows only offer "Unblock".
          onOpen: blocked ? null : () => context.push(userProfilePath(person.id)),
          actionLabel: blocked ? 'UNBLOCK' : (person.isFollowing ? 'FOLLOWING' : 'FOLLOW'),
          actionFilled: !blocked && !person.isFollowing,
          onReport: blocked
              ? () async {
                  final reason = await askReportReason(context, title: 'Report this runner');
                  if (reason == null || !context.mounted) return;
                  final out = await ref.read(socialActionsProvider.notifier).report(ReportKind.user, person.id, reason);
                  if (context.mounted) tellUser(context, out.error ?? 'Report sent. Thank you.');
                }
              : null,
          onAction: () async {
            final error = blocked ? await vm.unblock(person) : await vm.toggleFollow(person);
            if (context.mounted) tellUser(context, error);
          },
        ),
      ),
    );
  }
}
