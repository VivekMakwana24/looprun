import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:looprun/data/models/api_exception.dart';
import 'package:looprun/data/models/models.dart';
import 'package:looprun/data/providers.dart';
import 'package:looprun/data/services/token_store.dart';
import 'package:looprun/domain/recorder/run_recorder.dart';
import 'package:looprun/ui/profile/profile_view_model.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../fakes/fakes.dart';

void main() {
  late FakeApiService api;
  late MemoryStore store;
  late FakePermissionService permissions;
  late FakeLocationService location;
  late InMemoryTokenStore tokens;
  late ProviderContainer container;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    api = FakeApiService();
    store = MemoryStore();
    permissions = FakePermissionService();
    location = FakeLocationService();
    tokens = InMemoryTokenStore(const StoredSession(token: 't', userId: 'u1', userName: 'Ann'));
    container = ProviderContainer(overrides: [
      preferencesProvider.overrideWithValue(prefs),
      apiServiceProvider.overrideWithValue(api),
      runStoreProvider.overrideWithValue(store),
      uploadStoreProvider.overrideWithValue(store),
      locationServiceProvider.overrideWithValue(location),
      permissionServiceProvider.overrideWithValue(permissions),
      foregroundServiceProvider.overrideWithValue(FakeForegroundService()),
      tokenStoreProvider.overrideWithValue(tokens),
      googleAuthServiceProvider.overrideWithValue(FakeGoogleAuthService()),
    ]);
    await container.read(authRepositoryProvider).restore(); // signed in as u1, like MemoryStore
  });

  tearDown(() => container.dispose());

  test('opening the tab loads zones and the rest-day quota from the server', () async {
    api.serverZones = const [HomeZone(lat: 1, lng: 2, radiusM: 300)];
    api.freezeStatus = const FreezeStatus(usedDays: 12, quotaDays: 30, windowDays: 90);
    final sub = container.listen(profileViewModelProvider, (previous, next) {});
    expect(sub.read().loading, isTrue);
    expect(sub.read().freeze, isNull, reason: 'nothing is shown as a quota before the server answered');
    await settle();
    expect(sub.read().loading, isFalse);
    expect(sub.read().loadFailed, isFalse);
    expect(sub.read().zones.single.radiusM, 300);
    expect(sub.read().freeze!.usedDays, 12);
    expect(api.meCalls, 1);
  });

  test('when the server cannot be reached the tab says so and load() tries again', () async {
    api.meError = const ApiException(null, 'offline');
    final sub = container.listen(profileViewModelProvider, (previous, next) {});
    await settle();
    expect(sub.read().loadFailed, isTrue);
    expect(sub.read().loading, isFalse);
    expect(sub.read().freeze, isNull);

    api.meError = null;
    await container.read(profileViewModelProvider.notifier).load();
    expect(sub.read().loadFailed, isFalse);
    expect(sub.read().freeze, isNotNull);
  });

  test('adding a zone updates the state and says so', () async {
    final sub = container.listen(profileViewModelProvider, (previous, next) {});
    final vm = container.read(profileViewModelProvider.notifier);
    await vm.addZoneHere(500);
    expect(sub.read().zones.single.radiusM, 500);
    expect(sub.read().message, contains('never show your name'));
    expect(sub.read().busy, isFalse);
    expect(sub.read().messageSeq, 1);
    // The answer of the first GET /me (no zones) must not wipe the zone that was just added.
    await settle();
    expect(sub.read().zones.length, 1);
  });

  test('removing one zone keeps the others', () async {
    final sub = container.listen(profileViewModelProvider, (previous, next) {});
    final vm = container.read(profileViewModelProvider.notifier);
    await vm.addZoneHere(100);
    await vm.addZoneHere(200);
    await vm.removeZone(0);
    expect(sub.read().zones.single.radiusM, 200);
    expect(api.serverZones.single.radiusM, 200);
    expect(sub.read().message, 'Zone removed.');
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

  test('rest days: start, end, and a full quota is explained', () async {
    final sub = container.listen(profileViewModelProvider, (previous, next) {});
    final vm = container.read(profileViewModelProvider.notifier);
    api.freezeStatus = const FreezeStatus(freezeUntil: 1234, usedDays: 7, quotaDays: 30, windowDays: 90);
    await vm.setFreeze(7);
    expect(sub.read().freezeUntil, 1234);
    expect(sub.read().freeze!.usedDays, 7);
    expect(sub.read().message, contains('7 days'));

    api.freezeStatus = const FreezeStatus(usedDays: 7, quotaDays: 30, windowDays: 90);
    await vm.setFreeze(0);
    expect(sub.read().freezeUntil, isNull);
    expect(api.freezeCalls, [7, 0]);

    api.freezeError = const ApiException(409, 'quota');
    await vm.setFreeze(30);
    expect(sub.read().message, contains('rest days left'));
    expect(sub.read().freezeUntil, isNull);
  });

  test('deleting the account wipes local data and signs out', () async {
    await store.createRun('r', 1);
    final sub = container.listen(profileViewModelProvider, (previous, next) {});
    await container.read(profileViewModelProvider.notifier).deleteAccount();
    expect(api.deleted, isTrue);
    expect(store.runIds, isEmpty);
    expect(sub.read().zones, isEmpty);
    expect(container.read(authRepositoryProvider).token, isNull);
    expect(await tokens.read(), isNull);
  });

  test('while a run is being recorded, sign-out and account deletion are refused (review F7)', () async {
    final sub = container.listen(profileViewModelProvider, (previous, next) {});
    final vm = container.read(profileViewModelProvider.notifier);
    await container.read(runRepositoryProvider).start();
    expect(container.read(runRepositoryProvider).isRecording, isTrue);

    await vm.signOut();
    expect(container.read(authRepositoryProvider).token, 't');
    expect(sub.read().message, contains('Finish your run'));

    await vm.deleteAccount();
    expect(api.deleted, isFalse);
    expect(container.read(authRepositoryProvider).token, 't');

    location.emit(const GeoFix(lat: 50.0, lng: 8.7, t: 1, acc: 5));
    location.emit(const GeoFix(lat: 50.001, lng: 8.7, t: 2, acc: 5));
    await settle();
    await container.read(runRepositoryProvider).stop();
    await vm.signOut();
    expect(container.read(authRepositoryProvider).token, isNull);
  });
}
