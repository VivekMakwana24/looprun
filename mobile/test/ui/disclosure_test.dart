import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:looprun/app.dart';
import 'package:looprun/core/config.dart';
import 'package:looprun/data/providers.dart';
import 'package:looprun/data/services/token_store.dart';
import 'package:looprun/ui/disclosure/disclosure_screen.dart';
import 'package:looprun/ui/disclosure/disclosure_view_model.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../fakes/fakes.dart';

Future<ProviderScope> _scope(FakePermissionService permissions, Widget child, {FakeLinkService? linkService}) async {
  final links = linkService ?? FakeLinkService();
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  return ProviderScope(
    overrides: [
      preferencesProvider.overrideWithValue(prefs),
      permissionServiceProvider.overrideWithValue(permissions),
      apiServiceProvider.overrideWithValue(FakeApiService()),
      runStoreProvider.overrideWithValue(MemoryStore()),
      linkServiceProvider.overrideWithValue(links),
      privacyPolicyUrlProvider.overrideWithValue('https://looprun.example/privacy'),
      googleAuthServiceProvider.overrideWithValue(FakeGoogleAuthService()),
      tokenStoreProvider.overrideWithValue(InMemoryTokenStore(
        const StoredSession(token: 't', userId: 'u1', userName: 'dev'),
      )),
    ],
    child: child,
  );
}

void main() {
  testWidgets('signed-in user sees the disclosure before any permission prompt', (tester) async {
    final permissions = FakePermissionService();
    await tester.pumpWidget(await _scope(permissions, const LooprunApp()));
    await tester.pumpAndSettle();

    expect(find.byType(DisclosureScreen), findsOneWidget);
    expect(find.text(disclosureCollect), findsOneWidget);
    expect(find.text(disclosureWhen), findsOneWidget);
    expect(find.textContaining('switch to another app'), findsOneWidget);
    expect(find.byKey(const Key('disclosure_privacy_link')), findsOneWidget);
    expect(permissions.requests, 0);
  });

  testWidgets('permission is requested only after tapping agree', (tester) async {
    final permissions = FakePermissionService();
    await tester.pumpWidget(
      await _scope(permissions, const MaterialApp(home: DisclosureScreen())),
    );
    await tester.pump();
    expect(permissions.requests, 0);

    await tester.tap(find.byKey(const Key('disclosure_agree_button')));
    await tester.pumpAndSettle();

    expect(permissions.requests, 1);
    final container = ProviderScope.containerOf(tester.element(find.byType(DisclosureScreen)));
    expect(container.read(disclosureViewModelProvider), isTrue);
  });

  testWidgets('every text on the screen is exactly the text of the compliance document', (tester) async {
    final semantics = tester.ensureSemantics();
    final doc = File('../docs/compliance/location-disclosure.md').readAsStringSync();
    for (final s in [
      disclosureTitle,
      disclosureHeading,
      disclosureCollectTitle,
      disclosureWhyTitle,
      disclosureWhenTitle,
      disclosureSharingTitle,
      disclosureControlTitle,
      disclosureCollect,
      disclosureWhy,
      disclosureWhen,
      disclosureSharing('[MAP_TILE_PROVIDER]'),
      disclosureControl,
      disclosurePolicyLabel,
      disclosureAgreeLabel,
      disclosureDeclineLabel,
    ]) {
      expect(doc.contains(s), isTrue, reason: 'not in location-disclosure.md: "$s"');
    }

    await tester.pumpWidget(
      await _scope(FakePermissionService(), const MaterialApp(home: DisclosureScreen())),
    );
    await tester.pump();
    expect(find.text(disclosureHeading), findsOneWidget);
    for (final t in [
      disclosureCollect,
      disclosureWhy,
      disclosureWhen,
      disclosureSharing(AppConfig.mapTileProvider),
      disclosureControl,
    ]) {
      expect(find.text(t), findsOneWidget);
    }
    // Headings are the same strings, drawn in capitals by style only (screen readers get the string).
    for (final t in [disclosureTitle, disclosureCollectTitle, disclosureWhyTitle, disclosureWhenTitle,
        disclosureSharingTitle, disclosureControlTitle]) {
      expect(find.text(t.toUpperCase()), findsOneWidget, reason: t);
      expect(find.bySemanticsLabel(t), findsWidgets, reason: t);
    }
    expect(find.text(disclosureAgreeLabel), findsOneWidget);
    expect(find.text(disclosureDeclineLabel), findsOneWidget);
    expect(find.byKey(const Key('disclosure_decline_button')), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('the Privacy Policy link opens the browser before any permission prompt', (tester) async {
    final permissions = FakePermissionService();
    final links = FakeLinkService();
    await tester.pumpWidget(
      await _scope(permissions, const MaterialApp(home: DisclosureScreen()), linkService: links),
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('disclosure_privacy_link')));
    await tester.pump();
    expect(links.opened, ['https://looprun.example/privacy']);
    expect(permissions.requests, 0);
  });

  test('every text of the compliance document is on the screen (doc -> code)', () {
    final doc = File('../docs/compliance/location-disclosure.md').readAsStringSync();
    final start = doc.indexOf('## In-app screen text');
    final end = doc.indexOf('\n## ', start + 5);
    expect(start, greaterThanOrEqualTo(0));
    final section = doc.substring(start, end);

    final paragraphs = RegExp(r'^> (.+)$', multiLine: true).allMatches(section).map((m) => m.group(1)!.trim());
    final codeParagraphs = {
      disclosureCollect,
      disclosureWhy,
      disclosureWhen,
      disclosureSharing('[MAP_TILE_PROVIDER]'),
      disclosureControl,
    };
    expect(paragraphs.toSet(), codeParagraphs, reason: 'the paragraphs of the doc and of the screen differ');

    final headings = RegExp(r'^\*\*([^*:]+)\*\*\s*$', multiLine: true).allMatches(section).map((m) => m.group(1)!);
    expect(headings.toSet(), {
      disclosureCollectTitle,
      disclosureWhyTitle,
      disclosureWhenTitle,
      disclosureSharingTitle,
      disclosureControlTitle,
    });

    final quoted = RegExp('`([^`]+)`').allMatches(section).map((m) => m.group(1)!).toSet();
    final codeStrings = {
      disclosureTitle,
      disclosureHeading,
      disclosurePolicyLabel,
      disclosureAgreeLabel,
      disclosureDeclineLabel,
    };
    final keys = {'disclosure_agree_button', 'disclosure_decline_button', '[MAP_TILE_PROVIDER]', '[PRIVACY_POLICY_URL]', 'url_launcher'};
    final files = quoted.where((q) => q.contains('/') || q.endsWith('.dart') || q.endsWith('.md'));
    expect(quoted.difference(codeStrings).difference(keys).difference(files.toSet()), isEmpty,
        reason: 'a string in the doc is not on the screen');
    expect(codeStrings.difference(quoted), isEmpty);
  });
}
