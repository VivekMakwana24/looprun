import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:looprun/app.dart';
import 'package:looprun/data/services/permission_service.dart';
import 'package:looprun/core/providers.dart';
import 'package:looprun/data/services/token_store.dart';
import 'package:looprun/features/disclosure/disclosure_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FakeGateway implements PermissionService {
  int requests = 0;

  @override
  Future<bool> hasLocation() async => false;

  @override
  Future<bool> requestLocation() async {
    requests++;
    return true;
  }
}

Future<ProviderScope> _scope(FakeGateway gateway, Widget child) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  return ProviderScope(
    overrides: [
      prefsProvider.overrideWithValue(prefs),
      permissionGatewayProvider.overrideWithValue(gateway),
      tokenStoreProvider.overrideWithValue(InMemoryTokenStore(
        const StoredSession(token: 't', userId: 'u1', userName: 'dev'),
      )),
    ],
    child: child,
  );
}

void main() {
  testWidgets('signed-in user sees the disclosure before any permission prompt', (tester) async {
    final gateway = FakeGateway();
    await tester.pumpWidget(await _scope(gateway, const LooprunApp()));
    await tester.pumpAndSettle();

    expect(find.byType(DisclosureScreen), findsOneWidget);
    expect(find.text(disclosureCollect), findsOneWidget);
    expect(find.text(disclosureWhen), findsOneWidget);
    expect(find.textContaining('switch to another app'), findsOneWidget);
    expect(find.byKey(const Key('disclosure_privacy_link')), findsOneWidget);
    expect(gateway.requests, 0);
  });

  testWidgets('permission is requested only after tapping agree', (tester) async {
    final gateway = FakeGateway();
    await tester.pumpWidget(
      await _scope(gateway, const MaterialApp(home: DisclosureScreen())),
    );
    await tester.pump();
    expect(gateway.requests, 0);

    await tester.tap(find.byKey(const Key('disclosure_agree_button')));
    await tester.pumpAndSettle();

    expect(gateway.requests, 1);
    final container = ProviderScope.containerOf(tester.element(find.byType(DisclosureScreen)));
    expect(container.read(disclosureProvider), isTrue);
  });
}
