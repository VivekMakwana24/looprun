import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:looprun/data/providers.dart';
import 'package:looprun/data/repositories/battle_repository.dart';
import 'package:looprun/data/repositories/feed_repository.dart';
import 'package:looprun/data/repositories/notification_repository.dart';
import 'package:looprun/data/repositories/report_repository.dart';
import 'package:looprun/data/repositories/user_repository.dart';
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

  test('every Phase 1a provider built from the real apiServiceProvider can be read (no CircularDependencyError)', () {
    // The real API service and the real auth repository, as in the app: none of the new repositories may
    // reach back into the auth repository while the API service is being built.
    container.read(authRepositoryProvider);
    expect(container.read(feedRepositoryProvider), isA<FeedRepository>());
    expect(container.read(userRepositoryProvider), isA<UserRepository>());
    expect(container.read(battleRepositoryProvider), isA<BattleRepository>());
    expect(container.read(notificationRepositoryProvider), isA<NotificationRepository>());
    expect(container.read(reportRepositoryProvider), isA<ReportRepository>());
  });

  test('the new repositories can be read before anything else, in any order', () {
    final fresh = ProviderContainer(overrides: [
      tokenStoreProvider.overrideWithValue(InMemoryTokenStore()),
      googleAuthServiceProvider.overrideWithValue(FakeGoogleAuthService()),
    ]);
    addTearDown(fresh.dispose);
    expect(fresh.read(reportRepositoryProvider), isA<ReportRepository>());
    expect(fresh.read(notificationRepositoryProvider), isA<NotificationRepository>());
    expect(fresh.read(authRepositoryProvider), isNotNull);
    expect(fresh.read(userRepositoryProvider), isA<UserRepository>());
  });

  test('a request through a new repository carries the token the auth repository holds', () async {
    await tokens.write(const StoredSession(token: 't9', userId: 'u1', userName: 'Ann'));
    await container.read(authRepositoryProvider).restore();
    final api = container.read(apiServiceProvider) as DioApiService;
    expect(api.debugCurrentToken(), 't9');
    // Built from the same API service instance, so the same token source.
    expect(container.read(feedRepositoryProvider), isA<FeedRepository>());
    expect(container.read(apiServiceProvider), same(api));
  });
}
