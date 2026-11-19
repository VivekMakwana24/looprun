import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../data/models/social_models.dart';
import '../core/initials_avatar.dart';
import '../core/lr_page.dart';
import '../core/report_dialog.dart';
import '../core/social_actions_view_model.dart';
import '../core/widgets.dart';
import 'public_profile_view_model.dart';

/// A runner's public profile: initials, name, stats, follow, report, block. No photo, no runs, no places.
class PublicProfileScreen extends ConsumerWidget {
  const PublicProfileScreen({super.key, required this.userId});
  final String userId;

  Future<void> _report(BuildContext context, WidgetRef ref) async {
    final reason = await askReportReason(context, title: 'Report this runner');
    if (reason == null || !context.mounted) return;
    final error = await ref.read(publicProfileViewModelProvider(userId).notifier).report(reason);
    tellUser(context, error ?? 'Report sent. Thank you.');
  }

  Future<void> _block(BuildContext context, WidgetRef ref, Profile p) async {
    final ok = await askConfirm(
      context,
      title: 'Block ${p.name}?',
      text: '$blockExplanation They are not told.',
      confirmLabel: 'Block',
      confirmKey: const Key('confirm_block'),
      danger: true,
    );
    if (!ok || !context.mounted) return;
    final error = await ref.read(publicProfileViewModelProvider(userId).notifier).block();
    if (!context.mounted) return;
    if (error != null) {
      tellUser(context, error);
      return;
    }
    tellUser(context, '${p.name} is blocked.');
    Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.lr;
    final state = ref.watch(publicProfileViewModelProvider(userId));
    final vm = ref.read(publicProfileViewModelProvider(userId).notifier);
    final p = state.profile;

    Widget body;
    if (p == null && state.loading) {
      body = Center(child: CircularProgressIndicator(key: const Key('profile_loading'), color: c.accent));
    } else if (p == null) {
      body = Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Center(
          child: state.notFound
              ? const LrMessage(
                  key: Key('profile_not_found'),
                  title: 'This profile is not available',
                  text: 'The runner may have left Looprun.',
                )
              : LrMessage(
                  key: const Key('profile_error'),
                  title: state.offline ? "Can't reach the server" : 'This profile could not be loaded',
                  text: state.offline ? 'Check your connection.' : state.error,
                  actionLabel: 'Try again',
                  onAction: vm.load,
                ),
        ),
      );
    } else {
      body = _ProfileBody(
        profile: p,
        busy: state.busy,
        onFollow: () async => tellUser(context, await vm.toggleFollow()),
      );
    }

    return LrPage(
      title: p?.isMe == true ? 'YOU' : 'RUNNER',
      actions: [
        if (p != null && !p.isMe)
          PopupMenuButton<String>(
            key: const Key('profile_menu'),
            tooltip: 'More',
            icon: Icon(Icons.more_vert, color: c.text),
            constraints: const BoxConstraints(minWidth: 48),
            color: c.raised,
            onSelected: (a) => a == 'report' ? _report(context, ref) : _block(context, ref, p),
            itemBuilder: (_) => [
              PopupMenuItem(
                key: const Key('profile_report'),
                value: 'report',
                height: 48,
                child: Text('Report', style: LrText.body(15, color: c.text)),
              ),
              PopupMenuItem(
                key: const Key('profile_block'),
                value: 'block',
                height: 48,
                child: Text('Block', style: LrText.body(15, color: c.danger)),
              ),
            ],
          ),
      ],
      child: body,
    );
  }
}

class _ProfileBody extends StatelessWidget {
  const _ProfileBody({required this.profile, required this.busy, required this.onFollow});
  final Profile profile;
  final bool busy;
  final VoidCallback onFollow;

  @override
  Widget build(BuildContext context) {
    final c = context.lr;
    final p = profile;
    final joined = p.joinedAt == null
        ? null
        : 'Joined ${formatDayMonth(DateTime.fromMillisecondsSinceEpoch(p.joinedAt!))} '
            '${DateTime.fromMillisecondsSinceEpoch(p.joinedAt!).year}';
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      children: [
        Row(
          children: [
            InitialsAvatar(name: p.name, size: 72),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(p.name,
                      key: const Key('profile_name'),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: LrText.display(34, color: c.text, height: 1)),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      if (p.followsMe && !p.isMe) _Chip(key: const Key('follows_you_chip'), text: 'Follows you'),
                      if (joined != null) Text(joined, style: LrText.body(13, color: c.muted)),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        LrCard(
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(child: _StatCell(value: '${p.cellsHeld}', label: 'CELLS HELD', accent: true)),
                  Container(width: 1, height: 64, color: c.line),
                  Expanded(
                    child: _StatCell(
                      key: const Key('stat_weekly_rank'),
                      value: p.weeklyRank == null ? noValue : '#${p.weeklyRank}',
                      label: 'WEEKLY RANK',
                    ),
                  ),
                ],
              ),
              Container(height: 1, color: c.line),
              Row(
                children: [
                  Expanded(child: _StatCell(value: '${p.followersCount}', label: 'FOLLOWERS')),
                  Container(width: 1, height: 64, color: c.line),
                  Expanded(child: _StatCell(value: '${p.followingCount}', label: 'FOLLOWING')),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        if (!p.isMe)
          LrBox(
            key: const Key('follow_button'),
            onTap: busy ? null : onFollow,
            semanticLabel: p.isFollowing ? 'Following ${p.name}. Tap to unfollow' : 'Follow ${p.name}',
            color: p.isFollowing ? null : c.accent,
            borderColor: p.isFollowing ? c.line : null,
            radius: 20,
            height: 56,
            child: Text(
              p.isFollowing ? 'FOLLOWING' : 'FOLLOW',
              style: LrText.display(26, color: p.isFollowing ? c.text : c.onAccent, tracking: 0.03, height: 1),
            ),
          ),
        const SizedBox(height: 16),
        Text(
          p.isMe
              ? 'This is how other runners see you. They see your name and these numbers; runs only reach people who follow you.'
              : 'Runs, times and places stay private. Followers see a summary of each finished run after about half an hour.',
          style: LrText.body(13, color: c.muted, height: 1.4),
        ),
      ],
    );
  }
}

class _StatCell extends StatelessWidget {
  const _StatCell({super.key, required this.value, required this.label, this.accent = false});
  final String value;
  final String label;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: LrStat(value: value, label: label, size: 40, accent: accent),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({super.key, required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final c = context.lr;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(999), border: Border.all(color: c.line)),
      child: Text(text, style: LrText.label(13, color: c.text2, tracking: 0.1)),
    );
  }
}
