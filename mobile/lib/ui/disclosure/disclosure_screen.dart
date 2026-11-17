import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config.dart';
import '../../core/theme.dart';
import '../auth/auth_view_model.dart';
import '../core/links_view_model.dart';
import '../core/widgets.dart';
import 'disclosure_view_model.dart';

/// Texts must match docs/compliance/location-disclosure.md ("In-app screen text (must match code)").
/// The section headings are drawn in capitals by style only; the strings stay as in that document.
const String disclosureTitle = 'Your location';
const String disclosureHeading = 'Before we ask for location access';
const String disclosureCollectTitle = 'What we collect';
const String disclosureWhyTitle = 'Why';
const String disclosureWhenTitle = 'When';
const String disclosureSharingTitle = 'Sharing';
const String disclosureControlTitle = 'Your control';
const String disclosurePolicyLabel = 'Privacy Policy';
const String disclosureAgreeLabel = 'Agree and continue';
const String disclosureDeclineLabel = 'No thanks, sign out';
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
    // Asks for the permission first, then records the acceptance (which makes the router leave this screen).
    await ref.read(disclosureViewModelProvider.notifier).accept();
  }

  Future<void> _showPolicy() async {
    final links = ref.read(linksViewModelProvider);
    final opened = await links.openPrivacyPolicy();
    if (!opened && mounted) await showPrivacyPolicyFallback(context, links.privacyPolicyUrl);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.lr;
    final sections = <(String, String)>[
      (disclosureCollectTitle, disclosureCollect),
      (disclosureWhyTitle, disclosureWhy),
      (disclosureWhenTitle, disclosureWhen),
      (disclosureSharingTitle, disclosureSharing(AppConfig.mapTileProvider)),
      (disclosureControlTitle, disclosureControl),
    ];
    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 28, 24, 12),
                child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Icon(Icons.location_on_outlined, size: 18, color: c.accentText),
                      const SizedBox(width: 8),
                      Semantics(
                        header: true,
                        child: CapsLabel(disclosureTitle, style: LrText.label(14, color: c.accentText)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Semantics(
                    header: true,
                    child: Text(disclosureHeading,
                        style: LrText.display(38, color: c.text, tracking: 0.01, height: 1)),
                  ),
                  const SizedBox(height: 26),
                  for (var i = 0; i < sections.length; i++)
                    _Point(
                      title: sections[i].$1,
                      text: sections[i].$2,
                      last: i == sections.length - 1,
                    ),
                ],
              ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      key: const Key('disclosure_privacy_link'),
                      onPressed: _showPolicy,
                      style: TextButton.styleFrom(padding: EdgeInsets.zero),
                      child: Text(disclosurePolicyLabel,
                          style: LrText.body(15,
                              weight: FontWeight.w600, color: c.accentText, decoration: TextDecoration.underline)),
                    ),
                  ),
                  const SizedBox(height: 10),
                  LrBox(
                    key: const Key('disclosure_agree_button'),
                    onTap: _busy ? null : _agree,
                    color: c.accent,
                    radius: 22,
                    height: 62,
                    child: Text(disclosureAgreeLabel,
                        style: LrText.body(18, weight: FontWeight.w600, color: c.onAccent)),
                  ),
                  const SizedBox(height: 10),
                  LrBox(
                    key: const Key('disclosure_decline_button'),
                    onTap: _busy ? null : () => ref.read(authViewModelProvider.notifier).signOut(),
                    radius: 22,
                    height: 50,
                    child: Text(disclosureDeclineLabel,
                        style: LrText.body(16, weight: FontWeight.w500, color: c.text2)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One section on the timeline: a ringed dot (filled for the last), a line down to the next one.
class _Point extends StatelessWidget {
  const _Point({required this.title, required this.text, required this.last});
  final String title;
  final String text;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final c = context.lr;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 14,
            child: Column(
              children: [
                const SizedBox(height: 3),
                Container(
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: last ? c.accent : null,
                    border: last ? null : Border.all(color: c.accent, width: 3),
                  ),
                ),
                if (!last) Expanded(child: Container(width: 2, color: c.line)),
              ],
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: last ? 0 : 22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CapsLabel(title, style: LrText.label(17, color: c.text, tracking: 0.1)),
                  const SizedBox(height: 6),
                  Text(text, style: LrText.body(14, color: c.text2, height: 1.5)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
