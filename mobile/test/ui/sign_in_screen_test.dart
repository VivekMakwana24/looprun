import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:looprun/data/models/api_exception.dart';
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
      apiBaseUrlHintProvider.overrideWithValue(null),
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
    await tester.ensureVisible(find.byKey(const Key('dev_login_button')));
    await tester.tap(find.byKey(const Key('dev_login_button')));
    await tester.pump();
    await tester.pump();
    expect(api.idTokens, ['dev:dev']);
  });

  testWidgets('a failed Google sign-in shows the plain sentence under the button', (tester) async {
    final api = FakeApiService()..authError = const ApiException(null, 'SocketException: refused');
    await tester.pumpWidget(_app(devAuth: false, api: api));
    await tester.pump();
    await tester.ensureVisible(find.byKey(const Key('google_sign_in_button')));
    await tester.tap(find.byKey(const Key('google_sign_in_button')));
    await tester.pump();
    await tester.pump();
    expect(find.text("Can't reach the server. Check your connection."), findsOneWidget);
    expect(find.textContaining('SocketException'), findsNothing);
  });

  testWidgets('the copy of the mockup is there', (tester) async {
    await tester.pumpWidget(_app(devAuth: false));
    await tester.pump();
    expect(find.text('LOOPRUN'), findsOneWidget);
    expect(find.text('Run a loop. Fill the map.'), findsOneWidget);
    expect(find.text('Every cell inside becomes yours'), findsOneWidget);
    expect(find.text('Sign in with Google'), findsOneWidget);
    expect(tester.getSize(find.byKey(const Key('google_sign_in_button'))).height, greaterThanOrEqualTo(48));
  });
}
