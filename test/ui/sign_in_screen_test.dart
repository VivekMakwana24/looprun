import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:looprun/data/providers.dart';
import 'package:looprun/data/services/token_store.dart';
import 'package:looprun/ui/auth/sign_in_screen.dart';

import '../fakes/fakes.dart';

Widget _app({required bool devAuth, FakeApiService? api}) {
  return ProviderScope(
    overrides: [
      devAuthEnabledProvider.overrideWithValue(devAuth),
      tokenStoreProvider.overrideWithValue(InMemoryTokenStore()),
      apiServiceProvider.overrideWithValue(api ?? FakeApiService()),
      googleAuthServiceProvider.overrideWithValue(FakeGoogleAuthService()),
    ],
    child: const MaterialApp(home: SignInScreen()),
  );
}

void main() {
  testWidgets('dev login is hidden when DEV_AUTH is false', (tester) async {
    await tester.pumpWidget(_app(devAuth: false));
    await tester.pump();
    expect(find.byKey(const Key('google_sign_in_button')), findsOneWidget);
    expect(find.byKey(const Key('dev_login_button')), findsNothing);
    expect(find.byKey(const Key('dev_name_field')), findsNothing);
  });

  testWidgets('dev login is shown when DEV_AUTH is true', (tester) async {
    await tester.pumpWidget(_app(devAuth: true));
    await tester.pump();
    expect(find.byKey(const Key('google_sign_in_button')), findsOneWidget);
    expect(find.byKey(const Key('dev_login_button')), findsOneWidget);
  });

  testWidgets('dev login sends dev:<name> to the server', (tester) async {
    final api = FakeApiService();
    await tester.pumpWidget(_app(devAuth: true, api: api));
    await tester.pump();
    await tester.tap(find.byKey(const Key('dev_login_button')));
    await tester.pump();
    await tester.pump();
    expect(api.idTokens, ['dev:dev']);
  });
}
