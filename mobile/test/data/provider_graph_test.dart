import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:looprun/data/providers.dart';
import 'package:looprun/data/services/api_service.dart';
import 'package:looprun/data/services/token_store.dart';

import '../fakes/fakes.dart';

/// Uses the REAL apiServiceProvider and authRepositoryProvider (other tests replace the API with a fake,
/// which hid this): reading the token for a request must not walk back into the auth repository, or
/// Riverpod throws CircularDependencyError in debug builds and every request fails.
void main() {
  late InMemoryTokenStore tokens;
  late ProviderContainer container;

  setUp(() {
    tokens = InMemoryTokenStore();
    container = ProviderContainer(overrides: [
      tokenStoreProvider.overrideWithValue(tokens),
      googleAuthServiceProvider.overrideWithValue(FakeGoogleAuthService()),
    ]);
  });

  tearDown(() => container.dispose());

  test('the API client reads the token without a circular dependency', () {
    container.read(authRepositoryProvider);
    final api = container.read(apiServiceProvider) as DioApiService;
    expect(api.debugCurrentToken, returnsNormally);
    expect(api.debugCurrentToken(), isNull);
  });

  test('the token the auth repository restores is the one the API client sends', () async {
    await tokens.write(const StoredSession(token: 't1', userId: 'u1', userName: 'Ann'));
    await container.read(authRepositoryProvider).restore();
    final api = container.read(apiServiceProvider) as DioApiService;
    expect(api.debugCurrentToken(), 't1');

    await container.read(authRepositoryProvider).signOut();
    expect(api.debugCurrentToken(), isNull);
  });
}
