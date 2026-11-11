import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:looprun/data/models/api_exception.dart';
import 'package:looprun/data/providers.dart';
import 'package:looprun/data/services/token_store.dart';
import 'package:looprun/ui/profile/profile_view_model.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../fakes/fakes.dart';

void main() {
  late FakeApiService api;
  late MemoryStore store;
  late FakePermissionService permissions;
  late InMemoryTokenStore tokens;
  late ProviderContainer container;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    api = FakeApiService();
    store = MemoryStore();
    permissions = FakePermissionService();
    tokens = InMemoryTokenStore(const StoredSession(token: 't', userId: 'u1', userName: 'Ann'));
    container = ProviderContainer(overrides: [
      preferencesProvider.overrideWithValue(prefs),
      apiServiceProvider.overrideWithValue(api),
      runStoreProvider.overrideWithValue(store),
      locationServiceProvider.overrideWithValue(FakeLocationService()),
      permissionServiceProvider.overrideWithValue(permissions),
      tokenStoreProvider.overrideWithValue(tokens),
      googleAuthServiceProvider.overrideWithValue(FakeGoogleAuthService()),
    ]);
    await container.read(authRepositoryProvider).restore(); // signed in as u1, like MemoryStore
  });

  tearDown(() => container.dispose());

  test('adding a zone updates the state and says so', () async {
    final sub = container.listen(profileViewModelProvider, (previous, next) {});
    final vm = container.read(profileViewModelProvider.notifier);
    vm.setRadius(500);
    await vm.addZoneHere();
    expect(sub.read().zones.single.radiusM, 500);
    expect(sub.read().message, contains('never show your name'));
    expect(sub.read().busy, isFalse);
    expect(sub.read().messageSeq, 1);
  });

  test('a permission problem becomes a message, not an exception', () async {
    permissions.granted = false;
    final sub = container.listen(profileViewModelProvider, (previous, next) {});
    await container.read(profileViewModelProvider.notifier).addZoneHere();
    expect(sub.read().zones, isEmpty);
    expect(sub.read().message, contains('Location permission'));
  });

  test('a server error becomes a message', () async {
    api.zoneError = const ApiException(500, 'down');
    final sub = container.listen(profileViewModelProvider, (previous, next) {});
    await container.read(profileViewModelProvider.notifier).addZoneHere();
    expect(sub.read().message, contains('down'));
    expect(sub.read().zones, isEmpty);
  });

  test('freeze sets and clears freezeUntil', () async {
    final sub = container.listen(profileViewModelProvider, (previous, next) {});
    final vm = container.read(profileViewModelProvider.notifier);
    api.freezeUntil = 1234;
    await vm.setFreeze(7);
    expect(sub.read().freezeUntil, 1234);
    api.freezeUntil = null;
    await vm.setFreeze(0);
    expect(sub.read().freezeUntil, isNull);
  });

  test('deleting the account wipes local data and signs out', () async {
    await container.read(authRepositoryProvider).restore();
    await store.createRun('r', 1);
    final sub = container.listen(profileViewModelProvider, (previous, next) {});
    await container.read(profileViewModelProvider.notifier).deleteAccount();
    expect(api.deleted, isTrue);
    expect(store.runIds, isEmpty);
    expect(sub.read().zones, isEmpty);
    expect(container.read(authRepositoryProvider).token, isNull);
    expect(await tokens.read(), isNull);
  });
}
