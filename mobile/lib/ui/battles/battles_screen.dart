import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/format.dart';
import '../../core/routes.dart';
import '../../core/theme.dart';
import '../../data/models/social_models.dart';
import '../core/initials_avatar.dart';
import '../core/widgets.dart';
import 'battles_view_model.dart';

/// The RIVALS part of the BOARD lane: cells taken and lost in the last 7 days, and the per-runner list of
/// the last 30 days. Runners whose name is private are counted together, never named.
class BattlesScreen extends ConsumerWidget {
  const BattlesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.lr;
    final state = ref.watch(battlesViewModelProvider);
    final vm = ref.read(battlesViewModelProvider.notifier);
    final overview = state.overview;

    final children = <Widget>[];
    if (overview == null && state.error == null) {
      children.add(Padding(
        padding: const EdgeInsets.symmetric(vertical: 48),
        child: Center(child: CircularProgressIndicator(key: const Key('battles_loading'), color: c.accent)),
      ));
    } else if (overview == null) {
      children.add(LrMessage(
        key: const Key('battles_error'),
        title: state.offline ? "Can't reach the server" : 'Battles could not be loaded',
        text: state.offline ? 'Check your connection.' : state.error,
        actionLabel: 'Try again',
        onAction: vm.refresh,
      ));
    } else {
      final s = overview.summary;
      final r = overview.rivalry;
      if (state.error != null && state.offline) {
        children.add(const Padding(padding: EdgeInsets.only(bottom: 12), child: OfflineBanner()));
      }
      children.add(LrCard(
        key: const Key('battles_summary'),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('LAST ${s.days} DAYS', style: LrText.label(13, color: c.muted)),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(child: LrStat(value: '${s.taken}', label: 'TAKEN', size: 38, accent: true)),
                  Expanded(child: LrStat(value: '${s.lost}', label: 'LOST', size: 38)),
                  Expanded(child: LrStat(value: s.net > 0 ? '+${s.net}' : '${s.net}', label: 'NET', size: 38)),
                  Expanded(child: LrStat(value: '${s.battles}', label: 'BATTLES', size: 38)),
                ],
              ),
            ],
          ),
        ),
      ));
      children.add(const SizedBox(height: 20));
      children.add(Text('RIVALRIES, LAST ${r.days} DAYS', style: LrText.label(14, color: c.muted)));
      children.add(const SizedBox(height: 8));
      final un = r.unattributed;
      if (r.rivals.isEmpty && un.taken == 0 && un.lost == 0) {
        children.add(const LrMessage(
          key: Key('rivalry_empty'),
          title: 'No battles yet',
          text: 'Take cells from someone, or lose some, and the rivalry shows up here.',
        ));
      } else {
        for (final rival in r.rivals) {
          children.add(Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _RivalRow(
              key: Key('rival_${rival.user.id}'),
              rival: rival,
              onTap: () => context.push(userProfilePath(rival.user.id)),
            ),
          ));
        }
        if (un.taken > 0 || un.lost > 0) {
          children.add(_HiddenRow(counts: un));
        }
      }
      children.add(const SizedBox(height: 12));
      children.add(LrBox(
        key: const Key('all_rivals_link'),
        onTap: () => context.push(rivalsListPath),
        color: c.raised,
        borderColor: c.line,
        height: 52,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        alignment: Alignment.centerLeft,
        child: Row(
          children: [
            Expanded(child: Text('All rivals (last 30 days)', style: LrText.body(16, weight: FontWeight.w600, color: c.text))),
            Icon(Icons.chevron_right, color: c.muted),
          ],
        ),
      ));
      children.add(const SizedBox(height: 14));
      children.add(Text(
        'Runners with a private name, or cells inside a home zone, are counted but never named.',
        style: LrText.body(13, color: c.muted, height: 1.4),
      ));
    }

    return RefreshIndicator(
      color: c.accent,
      backgroundColor: c.surface,
      onRefresh: vm.refresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        children: children,
      ),
    );
  }
}

class _RivalRow extends StatelessWidget {
  const _RivalRow({super.key, required this.rival, required this.onTap});
  final Rival rival;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.lr;
    final last = rival.lastBattleAt == null
        ? null
        : formatAgo(DateTime.fromMillisecondsSinceEpoch(rival.lastBattleAt!));
    final net = rival.net > 0 ? '+${rival.net}' : '${rival.net}';
    return Semantics(
      button: true,
      label: '${rival.user.name}: you took ${rival.taken}, they took ${rival.lost}, net $net'
          '${last == null ? '' : ', last battle $last'}',
      excludeSemantics: true,
      child: Material(
        color: c.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18), side: BorderSide(color: c.line)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 68),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 14, 10),
              child: Row(
                children: [
                  InitialsAvatar(name: rival.user.name, size: 40),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(rival.user.name.isEmpty ? 'Runner' : rival.user.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: LrText.body(16, weight: FontWeight.w600, color: c.text)),
                        Text(
                          'You took ${rival.taken}, they took ${rival.lost}${last == null ? '' : '  -  $last'}',
                          style: LrText.body(13, color: c.muted),
                        ),
                      ],
                    ),
                  ),
                  Text(net, style: LrText.display(28, color: rival.net >= 0 ? c.accentText : c.danger, height: 1)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _HiddenRow extends StatelessWidget {
  const _HiddenRow({required this.counts});
  final BattleCounts counts;

  @override
  Widget build(BuildContext context) {
    final c = context.lr;
    return Semantics(
      label: 'Private runners: you took ${counts.taken}, they took ${counts.lost}',
      excludeSemantics: true,
      child: Container(
        key: const Key('rivalry_hidden'),
        constraints: const BoxConstraints(minHeight: 60),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: c.hidLine),
        ),
        child: Row(
          children: [
            Icon(Icons.visibility_off_outlined, size: 22, color: c.muted),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Private runners', style: LrText.body(16, weight: FontWeight.w600, color: c.text)),
                  Text('You took ${counts.taken}, they took ${counts.lost}', style: LrText.body(13, color: c.muted)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
