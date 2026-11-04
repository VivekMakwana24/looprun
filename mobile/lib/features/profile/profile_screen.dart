import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import '../../core/providers.dart';
import '../../data/models/api_exception.dart';
import '../../data/models/models.dart';
import '../auth/auth_controller.dart';
import '../leaderboard/leaderboard_sheet.dart';
import 'home_zones.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  double _radius = 200;
  int? _freezeUntil;
  bool _busy = false;

  void _toast(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _run(Future<void> Function() action) async {
    if (!mounted) return;
    setState(() => _busy = true);
    try {
      await action();
    } on ApiException catch (e) {
      _toast('Request failed: ${e.message}');
    } on StateError catch (e) {
      _toast(e.message);
    } catch (e) {
      _toast('Something went wrong: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _addZone() {
    return _run(() async {
      final gateway = ref.read(permissionGatewayProvider);
      if (!await gateway.hasLocation() && !await gateway.requestLocation()) {
        _toast('Location permission is needed to place a zone at your position.');
        return;
      }
      final p = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      );
      await ref
          .read(homeZonesProvider.notifier)
          .add(HomeZone(lat: p.latitude, lng: p.longitude, radiusM: _radius));
      _toast('Zone added. Runs inside it stay hidden from other players.');
    });
  }

  Future<void> _clearZones() {
    return _run(() async {
      await ref.read(homeZonesProvider.notifier).clear();
      _toast('All home zones removed.');
    });
  }

  Future<void> _freeze(int days) {
    return _run(() async {
      final until = await ref.read(apiClientProvider).setFreeze(days);
      if (!mounted) return;
      setState(() => _freezeUntil = until);
      _toast(days == 0 ? 'Freeze ended.' : 'Your cells will not decay for $days days.');
    });
  }

  Future<void> _deleteAccount() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete account?'),
        content: const Text(
            'This deletes your account, your runs and your cells on the server. Runs saved on this phone are removed too. This cannot be undone.'),
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
    await _run(() async {
      await ref.read(apiClientProvider).deleteAccount();
      await ref.read(databaseProvider).wipe();
      await ref.read(homeZonesProvider.notifier).forget();
      await ref.read(authProvider.notifier).signOut();
    });
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authProvider).user;
    final zones = ref.watch(homeZonesProvider);
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        ListTile(
          leading: const CircleAvatar(child: Icon(Icons.person)),
          title: Text(user?.name.isNotEmpty == true ? user!.name : 'Runner'),
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
          selected: {_radius},
          onSelectionChanged: (s) => setState(() => _radius = s.first),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: FilledButton(
                key: const Key('add_zone_button'),
                onPressed: _busy || zones.length >= maxHomeZones ? null : _addZone,
                child: Text('Add zone here (${zones.length}/$maxHomeZones)'),
              ),
            ),
            const SizedBox(width: 8),
            OutlinedButton(
              key: const Key('clear_zones_button'),
              onPressed: _busy || zones.isEmpty ? null : _clearZones,
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
                onPressed: _busy ? null : () => _freeze(d),
                child: Text('$d days'),
              ),
            TextButton(onPressed: _busy ? null : () => _freeze(0), child: const Text('End freeze')),
          ],
        ),
        if (_freezeUntil != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'Frozen until ${DateTime.fromMillisecondsSinceEpoch(_freezeUntil!).toLocal().toString().substring(0, 10)}',
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
          onTap: () => ref.read(authProvider.notifier).signOut(),
        ),
        ListTile(
          key: const Key('delete_account_tile'),
          leading: Icon(Icons.delete_forever, color: theme.colorScheme.error),
          title: Text('Delete account', style: TextStyle(color: theme.colorScheme.error)),
          onTap: _busy ? null : _deleteAccount,
        ),
      ],
    );
  }
}
