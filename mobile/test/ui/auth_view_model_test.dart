import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:looprun/core/app_exception.dart';
import 'package:looprun/data/models/api_exception.dart';
import 'package:looprun/data/providers.dart';
import 'package:looprun/data/services/google_auth_service.dart';
import 'package:looprun/data/services/token_store.dart';
import 'package:looprun/ui/auth/auth_view_model.dart';

import '../fakes/fakes.dart';

void main() {
  late FakeApiService api;
  late InMemoryTokenStore tokens;
  late FakeGoogleAuthService google;

  ProviderContainer make({bool devAuth = true, String? apiHint}) {
    return ProviderContainer(overrides: [
      apiBaseUrlHintProvider.overrideWithValue(apiHint),
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

  test('a server error shows a plain sentence, not the server text, and stays signed out', () async {
    api.authError = const ApiException(401, 'bad token');
    final c = make();
    addTearDown(c.dispose);
    final sub = c.listen(authViewModelProvider, (previous, next) {});
    await settle();
    await c.read(authViewModelProvider.notifier).signInWithGoogle();
    expect(sub.read().status, AuthStatus.signedOut);
    expect(sub.read().error, contains('did not accept'));
    expect(sub.read().error, isNot(contains('bad token')));
    expect(sub.read().busy, isFalse);
  });

  test('no network: "can\'t reach the server", with the address only when the build gives one', () async {
    api.authError = const ApiException(null, 'SocketException: Connection refused (OS Error ...)');
    var c = make(apiHint: 'http://10.0.2.2:8000');
    addTearDown(c.dispose);
    var sub = c.listen(authViewModelProvider, (previous, next) {});
    await settle();
    await c.read(authViewModelProvider.notifier).signInWithGoogle();
    expect(sub.read().error, startsWith("Can't reach the server. Check your connection."));
    expect(sub.read().error, contains('http://10.0.2.2:8000'));
    expect(sub.read().error, isNot(contains('SocketException')));

    c = make(); // release builds give no address
    addTearDown(c.dispose);
    sub = c.listen(authViewModelProvider, (previous, next) {});
    await settle();
    await c.read(authViewModelProvider.notifier).signInDev('x');
    expect(sub.read().error, "Can't reach the server. Check your connection.");
  });

  test('Google not set up for the build (ApiException 10) is said in plain words', () async {
    google.error = const AppException(googleNotSetUpMessage);
    final c = make();
    addTearDown(c.dispose);
    final sub = c.listen(authViewModelProvider, (previous, next) {});
    await settle();
    await c.read(authViewModelProvider.notifier).signInWithGoogle();
    expect(sub.read().error, 'Google sign-in is not set up for this build yet');
    expect(api.idTokens, isEmpty);
  });

  test('closing the Google dialog shows no error at all', () async {
    google.idToken = null;
    final c = make();
    addTearDown(c.dispose);
    final sub = c.listen(authViewModelProvider, (previous, next) {});
    await settle();
    await c.read(authViewModelProvider.notifier).signInWithGoogle();
    expect(sub.read().status, AuthStatus.signedOut);
    expect(sub.read().error, isNull);
    expect(sub.read().busy, isFalse);
  });

  test('an unexpected error never shows its raw text', () async {
    google.error = StateError('PlatformException(sign_in_failed, x, null, null)');
    final c = make();
    addTearDown(c.dispose);
    final sub = c.listen(authViewModelProvider, (previous, next) {});
    await settle();
    await c.read(authViewModelProvider.notifier).signInWithGoogle();
    expect(sub.read().error, 'Sign-in did not work. Please try again.');
  });

  test('signInErrorText covers the server answers', () {
    expect(signInErrorText(const ApiException(503, 'x')), contains('not set up on the server'));
    expect(signInErrorText(const ApiException(401, 'x'), dev: true), contains('dev login is switched off'));
    expect(signInErrorText(const ApiException(500, 'boom')), isNot(contains('boom')));
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
