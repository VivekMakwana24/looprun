import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../data/models/models.dart';
import '../auth/auth_view_model.dart';
import '../core/links_view_model.dart';
import '../core/theme_view_model.dart';
import '../core/widgets.dart';
import '../leaderboard/leaderboard_view_model.dart';
import 'profile_view_model.dart';

/// Lane 3: YOU. Numbers, theme, home zones, rest days and the account.
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  Future<void> _openPolicy(BuildContext context, WidgetRef ref) async {
    final links = ref.read(linksViewModelProvider);
    final opened = await links.openPrivacyPolicy();
    if (!opened && context.mounted) await showPrivacyPolicyFallback(context, links.privacyPolicyUrl);
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final ok = await askConfirm(
      context,
      title: 'Delete your account?',
      text: 'This deletes your account, your runs and your cell power on the server. Cells you hold pass to the '
          'strongest remaining runner or become free. Runs saved on this phone are removed too. '
          'This cannot be undone.',
      confirmLabel: 'Delete',
      confirmKey: const Key('confirm_delete_account'),
      danger: true,
    );
    if (!ok) return;
    await ref.read(profileViewModelProvider.notifier).deleteAccount();
  }

  Future<void> _addZone(BuildContext context, WidgetRef ref, double current) async {
    final radius = await showDialog<double>(
      context: context,
      builder: (ctx) {
        final c = ctx.lr;
        return SimpleDialog(
          title: const Text('Zone size'),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
              child: Text('The zone is centred on where you are now.',
                  style: LrText.body(14, color: c.text2, height: 1.4)),
            ),
            for (final r in homeZoneRadii)
              SimpleDialogOption(
                key: Key('zone_radius_${r.round()}'),
                onPressed: () => Navigator.pop(ctx, r),
                child: SizedBox(
                  height: 32,
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(r >= 1000 ? '1 km radius' : '${r.round()} m radius',
                            style: LrText.body(16, weight: FontWeight.w600, color: c.text)),
                      ),
                      if (r == current) Icon(Icons.check, size: 20, color: c.accentText),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
    if (radius == null) return;
    await ref.read(profileViewModelProvider.notifier).addZoneHere(radius);
  }

  Future<void> _startRest(BuildContext context, WidgetRef ref, FreezeStatus? freeze) async {
    final left = freeze != null && freeze.hasQuota ? freeze.quotaDays! - freeze.usedDays! : null;
    final days = await showDialog<int>(
      context: context,
      builder: (ctx) {
        final c = ctx.lr;
        return SimpleDialog(
          title: const Text('Start rest days'),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
              child: Text(
                left == null ? 'Your cells stop fading for this long.' : 'You have $left rest days left.',
                style: LrText.body(14, color: c.text2, height: 1.4),
              ),
            ),
            for (final d in restDayChoices)
              if (left == null || d <= left)
                SimpleDialogOption(
                  key: Key('rest_days_$d'),
                  onPressed: () => Navigator.pop(ctx, d),
                  child: SizedBox(
                    height: 32,
                    child: Text('$d days', style: LrText.body(16, weight: FontWeight.w600, color: c.text)),
                  ),
                ),
            if (left != null && left > 0 && !restDayChoices.contains(left) && left < restDayChoices.last)
              SimpleDialogOption(
                key: Key('rest_days_$left'),
                onPressed: () => Navigator.pop(ctx, left),
                child: SizedBox(
                  height: 32,
                  child: Text('$left days (all that is left)',
                      style: LrText.body(16, weight: FontWeight.w600, color: c.text)),
                ),
              ),
          ],
        );
      },
    );
    if (days == null) return;
    await ref.read(profileViewModelProvider.notifier).setFreeze(days);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen<ProfileState>(profileViewModelProvider, (previous, next) {
      final text = next.message;
      if (text != null && next.messageSeq != previous?.messageSeq) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
      }
    });
    final c = context.lr;
    final user = ref.watch(authViewModelProvider).user;
    final profile = ref.watch(profileViewModelProvider);
    final standing = ref.watch(myStandingProvider);
    final vm = ref.read(profileViewModelProvider.notifier);
    final busy = profile.busy;
    final h2 = LrText.label(14, color: c.muted);
    final p = LrText.body(14, color: c.text2, height: 1.4);
    final name = user != null && user.name.isNotEmpty ? user.name : 'Runner';

    return SafeArea(
      bottom: false,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(child: Text('YOU', style: LrText.display(60, color: c.text, tracking: 0.01, height: 0.88))),
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(name, style: LrText.body(17, weight: FontWeight.w600, color: c.text)),
                    const SizedBox(height: 2),
                    Text('Signed in', style: LrText.body(13, color: c.muted)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          LrCard(
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      child: LrStat(
                        value: standing.cells == null ? noValue : '${standing.cells}',
                        label: 'CELLS HELD',
                        size: 44,
                        accent: true,
                      ),
                    ),
                  ),
                  Container(width: 1, color: c.line),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      child: LrStat(
                        value: standing.rank == null ? noValue : '#${standing.rank}',
                        label: 'THIS WEEK',
                        size: 44,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (profile.loadFailed) ...[
            const SizedBox(height: 14),
            LrBox(
              key: const Key('profile_retry'),
              onTap: vm.load,
              color: c.raised,
              borderColor: c.line,
              radius: 14,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              alignment: Alignment.centerLeft,
              child: Row(
                children: [
                  Icon(Icons.cloud_off_outlined, size: 18, color: c.danger),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text("Can't reach the server. Zones shown are the ones saved on this phone.",
                        style: LrText.body(13, weight: FontWeight.w500, color: c.text2)),
                  ),
                  const SizedBox(width: 8),
                  Text('Try again', style: LrText.body(13, weight: FontWeight.w600, color: c.accentText)),
                ],
              ),
            ),
          ],
          const SizedBox(height: 20),
          Text('THEME', style: h2),
          const SizedBox(height: 10),
          const _ThemePicker(),
          const SizedBox(height: 20),
          Text('HOME ZONES', style: h2),
          const SizedBox(height: 4),
          Text('Cells inside a zone never show your name.', style: p),
          const SizedBox(height: 10),
          LrCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < profile.zones.length; i++)
                  Container(
                    key: Key('zone_row_$i'),
                    height: 54,
                    padding: const EdgeInsets.only(left: 16, right: 4),
                    decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c.line))),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 18,
                          height: 18,
                          child: CustomPaint(
                            painter: DashedBorderPainter(color: c.hidLine, strokeWidth: 2, dash: 3, circle: true),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text('Zone ${i + 1}', style: LrText.body(16, weight: FontWeight.w600, color: c.text)),
                        ),
                        Text(_radius(profile.zones[i].radiusM), style: LrText.body(14, color: c.muted)),
                        LrBox(
                          key: Key('remove_zone_$i'),
                          onTap: busy ? null : () => vm.removeZone(i),
                          semanticLabel: 'Remove zone ${i + 1}',
                          width: 48,
                          height: 48,
                          radius: 14,
                          child: Icon(Icons.close, size: 18, color: c.muted),
                        ),
                      ],
                    ),
                  ),
                LrBox(
                  key: const Key('add_zone_button'),
                  onTap: busy || profile.zones.length >= maxHomeZones
                      ? null
                      : () => _addZone(context, ref, profile.radiusM),
                  height: 52,
                  radius: 0,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          profile.zones.length >= maxHomeZones ? 'All zones used' : 'Add a zone where I am now',
                          style: LrText.body(15,
                              weight: FontWeight.w600,
                              color: profile.zones.length >= maxHomeZones ? c.muted : c.accentText),
                        ),
                      ),
                      Text('${profile.zones.length} of $maxHomeZones used',
                          style: LrText.body(15, weight: FontWeight.w500, color: c.muted)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Text('REST DAYS', style: h2),
          const SizedBox(height: 4),
          Text(
            'Injured or travelling? Pause the fading of your cells for up to '
            '${profile.freeze?.quotaDays ?? 30} days.',
            style: p,
          ),
          const SizedBox(height: 10),
          _RestDays(
            profile: profile,
            onStart: () => _startRest(context, ref, profile.freeze),
            onEnd: () => vm.setFreeze(0),
          ),
          const SizedBox(height: 20),
          Container(
            decoration: BoxDecoration(border: Border(top: BorderSide(color: c.line))),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _ListRow(
                  key: const Key('privacy_policy_link'),
                  label: 'Privacy Policy',
                  onTap: () => _openPolicy(context, ref),
                ),
                _ListRow(key: const Key('sign_out_button'), label: 'Sign out', onTap: busy ? null : vm.signOut),
                LrBox(
                  key: const Key('delete_account_tile'),
                  onTap: busy ? null : () => _confirmDelete(context, ref),
                  radius: 0,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  alignment: Alignment.centerLeft,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 44),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Delete my account', style: LrText.body(16, weight: FontWeight.w600, color: c.danger)),
                        const SizedBox(height: 2),
                        Text('Removes your runs and gives up your cells', style: LrText.body(13, color: c.muted)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

String _radius(double m) => m >= 1000 ? '${(m / 1000).toStringAsFixed(m % 1000 == 0 ? 0 : 1)} km radius' : '${m.round()} m radius';

class _ListRow extends StatelessWidget {
  const _ListRow({super.key, required this.label, required this.onTap});
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.lr;
    return Container(
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c.line))),
      child: LrBox(
        onTap: onTap,
        height: 52,
        radius: 0,
        alignment: Alignment.centerLeft,
        child: Text(label, style: LrText.body(16, weight: FontWeight.w500, color: c.text)),
      ),
    );
  }
}

class _RestDays extends StatelessWidget {
  const _RestDays({required this.profile, required this.onStart, required this.onEnd});
  final ProfileState profile;
  final VoidCallback onStart;
  final VoidCallback onEnd;

  @override
  Widget build(BuildContext context) {
    final c = context.lr;
    final freeze = profile.freeze;
    final until = freeze?.freezeUntil;
    final resting = until != null && until > DateTime.now().millisecondsSinceEpoch;
    final children = <Widget>[];
    if (freeze != null && freeze.hasQuota) {
      final used = freeze.usedDays!;
      final quota = freeze.quotaDays!;
      final fraction = (used / quota).clamp(0.0, 1.0).toDouble();
      children.add(Column(
        key: const Key('rest_quota'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Expanded(
                child: Text('$used of $quota days used', style: LrText.body(14, weight: FontWeight.w600, color: c.text)),
              ),
              if (freeze.windowDays != null)
                Text('in the last ${freeze.windowDays} days', style: LrText.body(14, color: c.muted)),
            ],
          ),
          const SizedBox(height: 8),
          Semantics(
            label: '$used of $quota rest days used',
            excludeSemantics: true,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: SizedBox(
                height: 8,
                child: Stack(
                  children: [
                    Positioned.fill(child: ColoredBox(color: c.line)),
                    FractionallySizedBox(widthFactor: fraction, heightFactor: 1, child: ColoredBox(color: c.accent)),
                  ],
                ),
              ),
            ),
          ),
        ],
      ));
    } else if (profile.loading) {
      children.add(Text('Loading your rest days...', style: LrText.body(14, color: c.muted)));
    } else {
      children.add(Text(
        profile.loadFailed ? 'Rest days could not be loaded.' : 'How many rest days are left is not known yet.',
        style: LrText.body(14, color: c.muted),
      ));
    }
    if (resting) {
      children.add(Text(
        'Resting until ${formatDayMonth(DateTime.fromMillisecondsSinceEpoch(until).toLocal())}. Your cells do not fade.',
        key: const Key('resting_until'),
        style: LrText.body(14, weight: FontWeight.w500, color: c.text2),
      ));
    }
    final noneLeft = freeze != null && freeze.hasQuota && freeze.usedDays! >= freeze.quotaDays!;
    children.add(LrBox(
      key: const Key('rest_days_button'),
      onTap: profile.busy || profile.loading || (!resting && noneLeft) ? null : (resting ? onEnd : onStart),
      color: c.raised,
      borderColor: c.line,
      radius: 18,
      height: 50,
      child: Text(
        resting ? 'End rest days' : (noneLeft ? 'No rest days left' : 'Start rest days'),
        style: LrText.body(16, weight: FontWeight.w600, color: noneLeft && !resting ? c.muted : c.text),
      ),
    ));
    return LrCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const SizedBox(height: 12),
            children[i],
          ],
        ],
      ),
    );
  }
}

class _ThemePicker extends ConsumerWidget {
  const _ThemePicker();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.lr;
    final current = ref.watch(themeViewModelProvider);
    return Row(
      children: [
        for (var i = 0; i < AppThemeId.values.length; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          Expanded(
            child: Builder(builder: (context) {
              final id = AppThemeId.values[i];
              final selected = id == current;
              final swatch = ThemeSwatch.of(id);
              return Semantics(
                selected: selected,
                button: true,
                label: '${themeLabel(id)} theme',
                excludeSemantics: true,
                child: Material(
                  color: c.surface,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                    side: BorderSide(color: selected ? c.accent : c.line, width: 2),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    key: Key('theme_swatch_${id.name}'),
                    onTap: () => ref.read(themeViewModelProvider.notifier).select(id),
                    child: SizedBox(
                      height: 78,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            width: 46,
                            height: 26,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: swatch.fill,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: swatch.border),
                            ),
                            child: Container(
                              width: 22,
                              height: 6,
                              decoration: BoxDecoration(color: swatch.bar, borderRadius: BorderRadius.circular(3)),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(themeLabel(id), style: LrText.body(14, weight: FontWeight.w600, color: c.text)),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }),
          ),
        ],
      ],
    );
  }
}
