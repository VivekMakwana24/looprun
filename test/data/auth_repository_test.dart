import 'package:flutter_test/flutter_test.dart';
import 'package:looprun/data/models/api_exception.dart';
import 'package:looprun/data/repositories/auth_repository.dart';
import 'package:looprun/data/services/token_store.dart';

import '../fakes/fakes.dart';

void main() {
  late FakeApiService api;
  late InMemoryTokenStore tokens;
  late FakeGoogleAuthService google;
  late AuthRepository repo;

  setUp(() {
    api = FakeApiService();
    tokens = InMemoryTokenStore();
    google = FakeGoogleAuthService();
    repo = AuthRepository(api: api, tokens: tokens, google: google);
  });

  tearDown(() async {
    await repo.dispose();
  });

  test('restore returns null when nothing is stored', () async {
    expect(await repo.restore(), isNull);
    expect(repo.token, isNull);
  });

  test('restore loads the stored session', () async {
    await tokens.write(const StoredSession(token: 't1', userId: 'u9', userName: 'Ann'));
    final s = await repo.restore();
    expect(s!.token, 't1');
    expect(s.user.name, 'Ann');
    expect(repo.token, 't1');
  });

  test('google sign-in exchanges the ID token, stores the session and publishes it', () async {
    final events = <Object?>[];
    final sub = repo.changes.listen(events.add);
    final s = await repo.signInWithGoogle();
    await settle();
    expect(api.idTokens, ['google-id-token']);
    expect(s!.token, 'tok');
    expect((await tokens.read())!.token, 'tok');
    expect(events.length, 1);
    await sub.cancel();
  });

  test('closing the Google dialog is not an error', () async {
    google.idToken = null;
    expect(await repo.signInWithGoogle(), isNull);
    expect(api.idTokens, isEmpty);
    expect(repo.token, isNull);
  });

  test('dev sign-in sends dev:<name>', () async {
    await repo.signInDev('anna');
    expect(api.idTokens, ['dev:anna']);
  });

  test('a server error keeps the user signed out', () async {
    api.authError = const ApiException(401, 'bad token');
    await expectLater(repo.signInDev('x'), throwsA(isA<ApiException>()));
    expect(repo.token, isNull);
    expect(await tokens.read(), isNull);
  });

  test('sign-out clears storage, Google and memory', () async {
    await repo.signInDev('anna');
    await repo.signOut();
    expect(repo.token, isNull);
    expect(await tokens.read(), isNull);
    expect(google.signOuts, 1);
  });

  test('expireSession signs out only when signed in', () async {
    await repo.expireSession();
    expect(google.signOuts, 0);
    await repo.signInDev('anna');
    await repo.expireSession();
    expect(repo.token, isNull);
    expect(google.signOuts, 1);
  });
}
