import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../data/models/social_models.dart';
import '../core/initials_avatar.dart';
import '../core/widgets.dart';
import 'run_card_text.dart';

/// What the card menu can do.
enum RunCardAction { report, block }

/// One run as a card: avatar, name, time, distance, moving time, pace, cells claimed and taken, kudos,
/// comments. Numbers only: no route line, no start or end point (the server never sends them).
class RunCardView extends StatelessWidget {
  const RunCardView({
    super.key,
    required this.card,
    required this.isMine,
    this.onOpen,
    this.onKudos,
    this.onComments,
    this.onProfile,
    this.onMenu,
  });

  final RunCard card;

  /// The caller's own run: no kudos button (the server refuses it), no report/block menu.
  final bool isMine;

  /// Tap on the card body.
  final VoidCallback? onOpen;
  final VoidCallback? onKudos;
  final VoidCallback? onComments;
  final VoidCallback? onProfile;
  final ValueChanged<RunCardAction>? onMenu;

  @override
  Widget build(BuildContext context) {
    final c = context.lr;
    final taken = takenFromText(card);
    final status = statusText(card);
    final when = formatRunDate(DateTime.fromMillisecondsSinceEpoch(card.startedAt));

    Widget stat(String value, String unit, String label) => Expanded(
          child: Semantics(
            label: '$label: $value $unit'.trim(),
            excludeSemantics: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Flexible(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(value, style: LrText.display(30, color: c.text, height: 1)),
                      ),
                    ),
                    if (unit.isNotEmpty) ...[
                      const SizedBox(width: 3),
                      Text(unit, style: LrText.label(13, color: c.muted, tracking: 0.08)),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(label, style: LrText.label(12, color: c.muted, tracking: 0.14)),
              ],
            ),
          ),
        );

    final d = card.distanceM;
    final body = Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              InkWell(
                onTap: onProfile,
                customBorder: const CircleBorder(),
                child: Semantics(
                  button: true,
                  label: 'Open profile of ${card.user.name}',
                  excludeSemantics: true,
                  child: SizedBox(
                    width: 48,
                    height: 48,
                    child: Center(child: InitialsAvatar(name: card.user.name, size: 44)),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Semantics(
                  label: 'Run by ${card.user.name}, $when',
                  excludeSemantics: true,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(card.user.name.isEmpty ? 'Runner' : card.user.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: LrText.body(16, weight: FontWeight.w600, color: c.text)),
                      const SizedBox(height: 1),
                      Text(when, style: LrText.body(13, color: c.muted)),
                    ],
                  ),
                ),
              ),
              if (status != null)
                Container(
                  key: const Key('run_card_status'),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: card.status == 'rejected' ? c.danger : c.line),
                  ),
                  child: Text(status, style: LrText.label(13, color: c.text2, tracking: 0.1)),
                ),
              if (!isMine && onMenu != null)
                PopupMenuButton<RunCardAction>(
                  key: const Key('run_card_menu'),
                  tooltip: 'More about this run',
                  icon: Icon(Icons.more_vert, color: c.muted),
                  iconSize: 22,
                  constraints: const BoxConstraints(minWidth: 48),
                  color: c.raised,
                  onSelected: onMenu,
                  itemBuilder: (_) => [
                    PopupMenuItem(
                      key: const Key('run_card_report'),
                      value: RunCardAction.report,
                      height: 48,
                      child: Text('Report this run', style: LrText.body(15, color: c.text)),
                    ),
                    PopupMenuItem(
                      key: const Key('run_card_block'),
                      value: RunCardAction.block,
                      height: 48,
                      child: Text('Block ${card.user.name}', style: LrText.body(15, color: c.danger)),
                    ),
                  ],
                ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              stat(d == null ? noValue : formatKm(d), d == null ? '' : 'KM', 'DISTANCE'),
              stat(formatMovingSeconds(card.movingSeconds), '', 'TIME'),
              stat(formatPaceSeconds(card.paceSecPerKm), card.paceSecPerKm == null ? '' : '/KM', 'PACE'),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 1, right: 8),
                child: Icon(Icons.hexagon_outlined, size: 18, color: card.cellsClaimed > 0 ? c.accentText : c.muted),
              ),
              Expanded(
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: claimedText(card),
                        style: LrText.body(15, weight: FontWeight.w600, color: card.cellsClaimed > 0 ? c.accentText : c.muted),
                      ),
                      if (taken != null)
                        TextSpan(text: ', $taken', style: LrText.body(15, color: c.text2)),
                    ],
                  ),
                  key: const Key('run_card_cells'),
                ),
              ),
            ],
          ),
        ],
      ),
    );

    final footer = Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 4),
      child: Row(
        children: [
          if (isMine)
            _CountChip(
              key: const Key('kudos_count_own'),
              icon: Icons.thumb_up_alt_outlined,
              count: card.kudosCount,
              label: '${card.kudosCount} kudos',
              active: false,
              onTap: null,
            )
          else
            _CountChip(
              key: const Key('kudos_button'),
              icon: card.kudosByMe ? Icons.thumb_up_alt : Icons.thumb_up_alt_outlined,
              count: card.kudosCount,
              label: card.kudosByMe ? 'Remove kudos, ${card.kudosCount} kudos' : 'Give kudos, ${card.kudosCount} kudos',
              active: card.kudosByMe,
              onTap: onKudos,
            ),
          _CountChip(
            key: const Key('comments_button'),
            icon: Icons.chat_bubble_outline,
            count: card.commentCount,
            label: '${card.commentCount} comments, open',
            active: false,
            onTap: onComments ?? onOpen,
          ),
        ],
      ),
    );

    return LrCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            key: const Key('run_card_body'),
            onTap: onOpen,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
            child: body,
          ),
          footer,
        ],
      ),
    );
  }
}

class _CountChip extends StatelessWidget {
  const _CountChip({
    super.key,
    required this.icon,
    required this.count,
    required this.label,
    required this.active,
    required this.onTap,
  });

  final IconData icon;
  final int count;
  final String label;
  final bool active;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.lr;
    final color = active ? c.accentText : c.text2;
    return LrBox(
      onTap: onTap,
      semanticLabel: label,
      radius: 14,
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 22, color: color),
          const SizedBox(width: 6),
          Text('$count', style: LrText.body(15, weight: FontWeight.w600, color: color)),
        ],
      ),
    );
  }
}
