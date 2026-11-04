import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:looprun/data/models/api_exception.dart';
import 'package:looprun/data/providers.dart';
import 'package:looprun/data/services/token_store.dart';
import 'package:looprun/ui/auth/auth_view_model.dart';

import '../fakes/fakes.dart';

void main() {
  late FakeApiService api;
  late InMemoryTokenStore tokens;
  late FakeGoogleAuthService google;

  ProviderContainer make({bool devAuth = true}) {
    return ProviderContainer(overrides: [
      apiServiceProvider.overrideWithValue(api),
      tokenStoreProvider.overrideWithValue(tokens),
      googleAuthServiceProvider.overrideWithValue(google),
      devAuthEnabledProvider.overrideWithValue(devAuth),
    ]);
  }

  setUp(() {
    api = FakeApiService();
    tokens = InMemoryTokenStore();
    google = FakeGoogleAuthService();
  });

  test('starts unknown, then signed out when nothing is stored', () async {
    final c = make();
    addTearDown(c.dispose);
    final sub = c.listen(authViewModelProvider, (previous, next) {});
    expect(sub.read().status, AuthStatus.unknown);
    await settle();
    expect(sub.read().status, AuthStatus.signedOut);
  });

  test('a stored session restores as signed in', () async {
    tokens = InMemoryTokenStore(const StoredSession(token: 't', userId: 'u', userName: 'Ann'));
    final c = make();
    addTearDown(c.dispose);
    final sub = c.listen(authViewModelProvider, (previous, next) {});
    await settle();
    expect(sub.read().status, AuthStatus.signedIn);
    expect(sub.read().user!.name, 'Ann');
  });

  test('google sign-in works and sign-out returns to signed out', () async {
    final c = make();
    addTearDown(c.dispose);
    final sub = c.listen(authViewModelProvider, (previous, next) {});
    await settle();
    final vm = c.read(authViewModelProvider.notifier);
    await vm.signInWithGoogle();
    await settle();
    expect(sub.read().status, AuthStatus.signedIn);
    await vm.signOut();
    await settle();
    expect(sub.read().status, AuthStatus.signedOut);
  });

  test('a server error shows a message and stays signed out', () async {
    api.authError = const ApiException(401, 'bad token');
    final c = make();
    addTearDown(c.dispose);
    final sub = c.listen(authViewModelProvider, (previous, next) {});
    await settle();
    await c.read(authViewModelProvider.notifier).signInWithGoogle();
    expect(sub.read().status, AuthStatus.signedOut);
    expect(sub.read().error, contains('bad token'));
    expect(sub.read().busy, isFalse);
  });

  test('dev sign-in is ignored when DEV_AUTH is off', () async {
    final c = make(devAuth: false);
    addTearDown(c.dispose);
    c.listen(authViewModelProvider, (previous, next) {});
    await settle();
    await c.read(authViewModelProvider.notifier).signInDev('x');
    expect(api.idTokens, isEmpty);
  });

  test('a lost session (401) signs the user out', () async {
    tokens = InMemoryTokenStore(const StoredSession(token: 't', userId: 'u', userName: 'Ann'));
    final c = make();
    addTearDown(c.dispose);
    final sub = c.listen(authViewModelProvider, (previous, next) {});
    await settle();
    await c.read(authRepositoryProvider).expireSession();
    await settle();
    expect(sub.read().status, AuthStatus.signedOut);
  });
}
