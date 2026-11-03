import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../auth/auth_controller.dart';

const String _prefKey = 'location_disclosure_accepted_v1';

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
    // Ask for the permission first, then record the acceptance (which swaps this screen out).
    await ref.read(permissionGatewayProvider).requestLocation();
    await ref.read(disclosureProvider.notifier).accept();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Your location')),
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
                      Text('Before we ask for location access', style: theme.textTheme.titleLarge),
                      const SizedBox(height: 16),
                      const _Point(
                        title: 'What we collect',
                        text:
                            'Your precise GPS position (latitude, longitude, time and accuracy) while you record a run, and whether your phone reports it as a mock location.',
                      ),
                      const _Point(
                        title: 'Why',
                        text:
                            'To find the loops you run, claim the map cells inside them, and check that runs are fair. Your track is sent to our server when you finish a run.',
                      ),
                      const _Point(
                        title: 'When',
                        text:
                            'Only while a run is active. Looprun shows a notification and keeps recording in a foreground service while you run, even if you lock the screen. It never records in the background when no run is active.',
                      ),
                      const _Point(
                        title: 'Your control',
                        text:
                            'You can hide places such as your home with Home zones in Profile, and delete your account and runs at any time.',
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
