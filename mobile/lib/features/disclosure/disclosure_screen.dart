import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config.dart';
import '../../core/providers.dart';
import '../auth/auth_controller.dart';

const String _prefKey = 'location_disclosure_accepted_v1';

/// Texts must match docs/compliance/location-disclosure.md ("In-app screen text (must match code)").
const String disclosureTitle = 'Your location';
const String disclosureHeading = 'Before we ask for location access';
const String disclosureCollect =
    'Your precise GPS position (latitude, longitude, time and accuracy) while you record a run, '
    'and whether your phone reports it as a mock location. We also read your current position once '
    'when the map opens, to centre it on you, and once when you add a home zone, to place it.';
const String disclosureWhy =
    'To find the loops you run, claim the map cells inside them, and check that runs are fair. '
    'Your track is sent to our server when you finish a run. The centre point of a home zone is also '
    'stored on our server, so your name stays hidden there.';
const String disclosureWhen =
    'While a run is active, Looprun shows a notification and keeps recording even if you lock the '
    'screen or switch to another app. Outside a run it reads your location only for the map and home '
    'zone actions above. It never records in the background when no run is active.';
const String disclosureControl =
    'You can hide places such as your home with Home zones in Profile, and delete your account and '
    'runs at any time.';

String disclosureSharing(String tileProvider) =>
    'We do not show ads and we do not share your location with anyone. Other players see which cells '
    'you own, never your route. The map images are loaded from $tileProvider, which can see your IP '
    'address and the area you view.';

class DisclosureController extends Notifier<bool> {
  @override
  bool build() => ref.watch(prefsProvider).getBool(_prefKey) ?? false;

  Future<void> accept() async {
    await ref.read(prefsProvider).setBool(_prefKey, true);
    state = true;
  }
}

final disclosureProvider = NotifierProvider<DisclosureController, bool>(DisclosureController.new);

/// Shown before any location or notification permission prompt.
/// The system prompt is only triggered by the "Agree and continue" button.
class DisclosureScreen extends ConsumerStatefulWidget {
  const DisclosureScreen({super.key});

  @override
  ConsumerState<DisclosureScreen> createState() => _DisclosureScreenState();
}

class _DisclosureScreenState extends ConsumerState<DisclosureScreen> {
  bool _busy = false;

  Future<void> _agree() async {
    setState(() => _busy = true);
    try {
      // Ask for the permission first, then record the acceptance (which swaps this screen out).
      await ref.read(permissionGatewayProvider).requestLocation();
    } catch (_) {
      // Location is asked for again when a run starts, so do not block the user here.
    }
    await ref.read(disclosureProvider.notifier).accept();
  }

  void _showPolicy() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Privacy Policy'),
        content: SelectableText(AppConfig.privacyPolicyUrl),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close'))],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text(disclosureTitle)),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(disclosureHeading, style: theme.textTheme.titleLarge),
                      const SizedBox(height: 16),
                      const _Point(title: 'What we collect', text: disclosureCollect),
                      const _Point(title: 'Why', text: disclosureWhy),
                      const _Point(title: 'When', text: disclosureWhen),
                      _Point(
                        title: 'Sharing',
                        text: disclosureSharing(AppConfig.mapTileProvider),
                      ),
                      const _Point(title: 'Your control', text: disclosureControl),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton(
                          key: const Key('disclosure_privacy_link'),
                          onPressed: _showPolicy,
                          child: const Text('Privacy Policy'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              FilledButton(
                key: const Key('disclosure_agree_button'),
                onPressed: _busy ? null : _agree,
                child: const Text('Agree and continue'),
              ),
              TextButton(
                key: const Key('disclosure_decline_button'),
                onPressed: _busy ? null : () => ref.read(authProvider.notifier).signOut(),
                child: const Text('No thanks, sign out'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Point extends StatelessWidget {
  const _Point({required this.title, required this.text});
  final String title;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 4),
          Text(text),
        ],
      ),
    );
  }
}
