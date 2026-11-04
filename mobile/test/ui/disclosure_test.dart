import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:looprun/app.dart';
import 'package:looprun/data/providers.dart';
import 'package:looprun/data/services/token_store.dart';
import 'package:looprun/ui/disclosure/disclosure_screen.dart';
import 'package:looprun/ui/disclosure/disclosure_view_model.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../fakes/fakes.dart';

Future<ProviderScope> _scope(FakePermissionService permissions, Widget child) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  return ProviderScope(
    overrides: [
      preferencesProvider.overrideWithValue(prefs),
      permissionServiceProvider.overrideWithValue(permissions),
      apiServiceProvider.overrideWithValue(FakeApiService()),
      runStoreProvider.overrideWithValue(MemoryStore()),
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
}
