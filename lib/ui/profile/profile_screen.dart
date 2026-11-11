import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/auth_view_model.dart';
import '../leaderboard/leaderboard_sheet.dart';
import 'profile_view_model.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete account?'),
        content: const Text(
            'This deletes your account, your runs and your cell power on the server. Cells you hold pass to the '
            'strongest remaining player or become free. Runs saved on this phone are removed too. '
            'This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            key: const Key('confirm_delete_account'),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(profileViewModelProvider.notifier).deleteAccount();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen<ProfileState>(profileViewModelProvider, (previous, next) {
      final text = next.message;
      if (text != null && next.messageSeq != previous?.messageSeq) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
      }
    });

    final user = ref.watch(authViewModelProvider).user;
    final profile = ref.watch(profileViewModelProvider);
    final vm = ref.read(profileViewModelProvider.notifier);
    final busy = profile.busy;
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        ListTile(
          leading: const CircleAvatar(child: Icon(Icons.person)),
          title: Text(user != null && user.name.isNotEmpty ? user.name : 'Runner'),
          subtitle: const Text('Signed in'),
        ),
        const Divider(),
        Text('Home zones', style: theme.textTheme.titleMedium),
        const SizedBox(height: 4),
        const Text(
            'Other players never see runs or cells inside a home zone. Zones are centred on where you are now.'),
        const SizedBox(height: 12),
        SegmentedButton<double>(
          segments: const [
            ButtonSegment(value: 100, label: Text('100 m')),
            ButtonSegment(value: 200, label: Text('200 m')),
            ButtonSegment(value: 500, label: Text('500 m')),
            ButtonSegment(value: 1000, label: Text('1 km')),
          ],
          selected: {profile.radiusM},
          onSelectionChanged: (s) => vm.setRadius(s.first),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: FilledButton(
                key: const Key('add_zone_button'),
                onPressed: busy || profile.zones.length >= maxHomeZones ? null : vm.addZoneHere,
                child: Text('Add zone here (${profile.zones.length}/$maxHomeZones)'),
              ),
            ),
            const SizedBox(width: 8),
            OutlinedButton(
              key: const Key('clear_zones_button'),
              onPressed: busy || profile.zones.isEmpty ? null : vm.clearZones,
              child: const Text('Clear all'),
            ),
          ],
        ),
        const Divider(height: 32),
        Text('Freeze decay', style: theme.textTheme.titleMedium),
        const SizedBox(height: 4),
        const Text('Going on holiday or injured? Pause the slow loss of your cells.'),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            for (final d in const [7, 14, 30])
              OutlinedButton(
                onPressed: busy ? null : () => vm.setFreeze(d),
                child: Text('$d days'),
              ),
            TextButton(onPressed: busy ? null : () => vm.setFreeze(0), child: const Text('End freeze')),
          ],
        ),
        if (profile.freezeUntil != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'Frozen until ${DateTime.fromMillisecondsSinceEpoch(profile.freezeUntil!).toLocal().toString().substring(0, 10)}',
            ),
          ),
        const Divider(height: 32),
        ListTile(
          leading: const Icon(Icons.emoji_events_outlined),
          title: const Text('Weekly leaderboard'),
          onTap: () => showLeaderboardSheet(context),
        ),
        ListTile(
          leading: const Icon(Icons.logout),
          title: const Text('Sign out'),
          onTap: () => ref.read(authViewModelProvider.notifier).signOut(),
        ),
        ListTile(
          key: const Key('delete_account_tile'),
          leading: Icon(Icons.delete_forever, color: theme.colorScheme.error),
          title: Text('Delete account', style: TextStyle(color: theme.colorScheme.error)),
          onTap: busy ? null : () => _confirmDelete(context, ref),
        ),
      ],
    );
  }
}
