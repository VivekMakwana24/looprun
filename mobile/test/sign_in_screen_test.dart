import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:looprun/core/providers.dart';
import 'package:looprun/core/token_store.dart';
import 'package:looprun/features/auth/sign_in_screen.dart';

Widget _app({required bool devAuth}) {
  return ProviderScope(
    overrides: [
      devAuthEnabledProvider.overrideWithValue(devAuth),
      tokenStoreProvider.overrideWithValue(InMemoryTokenStore()),
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
}
