import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/format.dart';
import '../../core/routes.dart';
import '../../core/theme.dart';
import '../../data/models/social_models.dart';
import '../auth/auth_view_model.dart';
import '../core/initials_avatar.dart';
import '../core/lr_page.dart';
import '../core/report_dialog.dart';
import '../core/social_actions_view_model.dart';
import '../core/widgets.dart';
import 'feed_screen.dart';
import 'run_card_view.dart';
import 'run_detail_view_model.dart';

/// One run with its comments. Comments can be added and (own, or any on your own run) deleted; other
/// people's comments and runs can be reported, and their authors blocked.
class RunDetailScreen extends ConsumerStatefulWidget {
  const RunDetailScreen({super.key, required this.runId, this.card});
  final String runId;
  final RunCard? card;

  @override
  ConsumerState<RunDetailScreen> createState() => _RunDetailScreenState();
}

class _RunDetailScreenState extends ConsumerState<RunDetailScreen> {
  final TextEditingController _text = TextEditingController();

  RunDetailArgs get _args => RunDetailArgs(widget.runId, widget.card);

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final vm = ref.read(runDetailViewModelProvider(_args).notifier);
    final error = await vm.post(_text.text);
    if (!mounted) return;
    if (error == null) {
      _text.clear();
      setState(() {});
    } else {
      tellUser(context, error);
    }
  }

  Future<void> _commentMenu(Comment comment, String action) async {
    final vm = ref.read(runDetailViewModelProvider(_args).notifier);
    final actions = ref.read(socialActionsProvider.notifier);
    switch (action) {
      case 'delete':
        {
          final ok = await askConfirm(
            context,
            title: 'Delete this comment?',
            text: 'It is removed for everyone.',
            confirmLabel: 'Delete',
            confirmKey: const Key('confirm_delete_comment'),
            danger: true,
          );
          if (!ok || !mounted) return;
          tellUser(context, await vm.deleteComment(comment));
          break;
        }
      case 'report':
        {
          final reason = await askReportReason(context, title: 'Report this comment');
          if (reason == null || !mounted) return;
          final out = await actions.report(ReportKind.comment, comment.id, reason);
          tellUser(context, out.error ?? 'Report sent. Thank you.');
          break;
        }
      case 'block':
        {
          final ok = await askConfirm(
            context,
            title: 'Block ${comment.user.name}?',
            text: 'You will not see each other in the feed, comments or search.',
            confirmLabel: 'Block',
            confirmKey: const Key('confirm_block'),
            danger: true,
          );
          if (!ok || !mounted) return;
          final out = await actions.block(comment.user.id);
          if (out.ok) vm.removeCommentsOf(comment.user.id);
          tellUser(context, out.error ?? '${comment.user.name} is blocked.');
          break;
        }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.lr;
    final state = ref.watch(runDetailViewModelProvider(_args));
    final vm = ref.read(runDetailViewModelProvider(_args).notifier);
    final myId = ref.watch(authViewModelProvider.select((s) => s.user?.id));
    final card = state.card;
    final mine = card != null && card.user.id == myId;

    final children = <Widget>[
      if (card != null)
        RunCardView(
          key: const Key('detail_card'),
          card: card,
          isMine: mine,
          onProfile: () => context.push(userProfilePath(card.user.id)),
          onKudos: () async => tellUser(context, await vm.toggleKudos()),
          onMenu: (action) async {
            final blocked = await runCardMenuAction(context, ref, card, action);
            if (blocked && context.mounted) Navigator.of(context).maybePop();
          },
        )
      else if (state.loading && !state.loaded)
        const SizedBox.shrink(),
      const SizedBox(height: 20),
      Text('COMMENTS', style: LrText.label(14, color: c.muted)),
      const SizedBox(height: 8),
    ];

    if (state.offline && state.loaded) {
      children.add(const Padding(padding: EdgeInsets.only(bottom: 10), child: OfflineBanner()));
    }
    if (!state.loaded && state.error == null) {
      children.add(Padding(
        padding: const EdgeInsets.symmetric(vertical: 32),
        child: Center(child: CircularProgressIndicator(key: const Key('comments_loading'), color: c.accent)),
      ));
    } else if (!state.loaded && state.error != null) {
      children.add(LrMessage(
        key: const Key('comments_error'),
        title: state.offline ? "Can't reach the server" : 'Comments could not be loaded',
        text: state.offline ? 'Check your connection.' : state.error,
        actionLabel: 'Try again',
        onAction: vm.refresh,
      ));
    } else if (state.comments.isEmpty) {
      children.add(const LrMessage(
        key: Key('comments_empty'),
        title: 'No comments yet',
        text: 'Say something nice.',
      ));
    } else {
      for (final comment in state.comments) {
        children.add(_CommentRow(
          key: Key('comment_${comment.id}'),
          comment: comment,
          isMine: comment.user.id == myId,
          onProfile: () => context.push(userProfilePath(comment.user.id)),
          onMenu: (a) => _commentMenu(comment, a),
        ));
      }
      if (state.loadingMore) {
        children.add(Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Center(child: CircularProgressIndicator(strokeWidth: 3, color: c.accent)),
        ));
      } else if (state.hasMore) {
        children.add(Center(
          child: LrBox(
            key: const Key('comments_load_more'),
            onTap: vm.loadMore,
            color: c.raised,
            borderColor: c.line,
            height: 48,
            padding: const EdgeInsets.symmetric(horizontal: 22),
            child: Text('Load more comments', style: LrText.body(15, weight: FontWeight.w600, color: c.text)),
          ),
        ));
      }
    }

    return LrPage(
      title: 'RUN',
      child: Column(
        children: [
          Expanded(
            child: RefreshIndicator(
              color: c.accent,
              backgroundColor: c.surface,
              onRefresh: vm.refresh,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                children: children,
              ),
            ),
          ),
          _Composer(
            controller: _text,
            posting: state.posting,
            onChanged: () => setState(() {}),
            onSend: _text.text.trim().isEmpty ? null : _send,
          ),
        ],
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({required this.controller, required this.posting, required this.onChanged, required this.onSend});
  final TextEditingController controller;
  final bool posting;
  final VoidCallback onChanged;
  final VoidCallback? onSend;

  @override
  Widget build(BuildContext context) {
    final c = context.lr;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
      decoration: BoxDecoration(color: c.surface, border: Border(top: BorderSide(color: c.line))),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              key: const Key('comment_field'),
              controller: controller,
              maxLength: 500,
              maxLines: 1,
              textInputAction: TextInputAction.send,
              onChanged: (_) => onChanged(),
              onSubmitted: (_) => onSend?.call(),
              style: LrText.body(15, color: c.text),
              decoration: InputDecoration(
                hintText: 'Add a comment',
                counterText: '',
                border: InputBorder.none,
                hintStyle: LrText.body(15, color: c.muted),
              ),
            ),
          ),
          if (posting)
            const SizedBox(width: 48, height: 48, child: Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 3))))
          else
            LrIconButton(
              key: const Key('comment_send'),
              icon: Icons.send,
              semanticLabel: 'Send comment',
              onTap: onSend,
            ),
        ],
      ),
    );
  }
}

class _CommentRow extends StatelessWidget {
  const _CommentRow({
    super.key,
    required this.comment,
    required this.isMine,
    required this.onProfile,
    required this.onMenu,
  });

  final Comment comment;
  final bool isMine;
  final VoidCallback onProfile;
  final ValueChanged<String> onMenu;

  @override
  Widget build(BuildContext context) {
    final c = context.lr;
    final when = formatAgo(DateTime.fromMillisecondsSinceEpoch(comment.createdAt));
    final hasMenu = comment.canDelete || !isMine;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c.line))),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: onProfile,
            customBorder: const CircleBorder(),
            child: Semantics(
              button: true,
              label: 'Open profile of ${comment.user.name}',
              excludeSemantics: true,
              child: SizedBox(
                width: 48,
                height: 48,
                child: Center(child: InitialsAvatar(name: comment.user.name, size: 36)),
              ),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Semantics(
                label: '${comment.user.name}, $when: ${comment.text}',
                excludeSemantics: true,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(comment.user.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: LrText.body(14, weight: FontWeight.w600, color: c.text)),
                        ),
                        const SizedBox(width: 8),
                        Text(when, style: LrText.body(12, color: c.muted)),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(comment.text, style: LrText.body(15, color: c.text2, height: 1.35)),
                    if (comment.hidden)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text('Hidden by moderators. Only you can see this.',
                            key: const Key('comment_hidden_note'),
                            style: LrText.body(12, color: c.danger)),
                      ),
                  ],
                ),
              ),
            ),
          ),
          if (hasMenu)
            PopupMenuButton<String>(
              key: Key('comment_menu_${comment.id}'),
              tooltip: 'More about this comment',
              icon: Icon(Icons.more_vert, color: c.muted),
              iconSize: 20,
              constraints: const BoxConstraints(minWidth: 48),
              color: c.raised,
              onSelected: onMenu,
              itemBuilder: (_) => [
                if (comment.canDelete)
                  PopupMenuItem(
                    key: const Key('comment_delete'),
                    value: 'delete',
                    height: 48,
                    child: Text('Delete', style: LrText.body(15, color: c.text)),
                  ),
                if (!isMine)
                  PopupMenuItem(
                    key: const Key('comment_report'),
                    value: 'report',
                    height: 48,
                    child: Text('Report', style: LrText.body(15, color: c.text)),
                  ),
                if (!isMine)
                  PopupMenuItem(
                    key: const Key('comment_block'),
                    value: 'block',
                    height: 48,
                    child: Text('Block ${comment.user.name}', style: LrText.body(15, color: c.danger)),
                  ),
              ],
            )
          else
            const SizedBox(width: 48),
        ],
      ),
    );
  }
}
