import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:looprun/data/providers.dart';
import 'package:looprun/data/services/token_store.dart';
import 'package:looprun/domain/recorder/run_recorder.dart';
import 'package:looprun/ui/run/run_view_model.dart';

import '../fakes/fakes.dart';

void main() {
  late MemoryStore store;
  late FakeLocationService location;
  late FakeApiService api;
  late ProviderContainer container;

  setUp(() {
    store = MemoryStore();
    location = FakeLocationService();
    api = FakeApiService();
    container = ProviderContainer(overrides: [
      runStoreProvider.overrideWithValue(store),
      uploadStoreProvider.overrideWithValue(store),
      locationServiceProvider.overrideWithValue(location),
      permissionServiceProvider.overrideWithValue(FakePermissionService()),
      foregroundServiceProvider.overrideWithValue(FakeForegroundService()),
      apiServiceProvider.overrideWithValue(api),
      tokenStoreProvider.overrideWithValue(
        InMemoryTokenStore(const StoredSession(token: 't', userId: 'u1', userName: 'Ann')),
      ),
      googleAuthServiceProvider.overrideWithValue(FakeGoogleAuthService()),
    ]);
  });

  tearDown(() => container.dispose());

  test('the view model follows the repository: start, record, stop, acknowledge', () async {
    await container.read(authRepositoryProvider).restore(); // signed in as u1, the store's account
    final sub = container.listen(runViewModelProvider, (previous, next) {});
    final vm = container.read(runViewModelProvider.notifier);
    expect(sub.read().status, RecorderStatus.idle);

    await vm.start();
    await settle();
    expect(sub.read().status, RecorderStatus.recording);

    location.emit(const GeoFix(lat: 50.0, lng: 8.7, t: 1, acc: 5));
    location.emit(const GeoFix(lat: 50.001, lng: 8.7, t: 2, acc: 5));
    await settle();
    expect(sub.read().path.length, 2);
    expect(sub.read().distanceM, greaterThan(100));

    await vm.stop();
    await settle();
    expect(sub.read().status, RecorderStatus.finished);
    final id = sub.read().finishedRunId;
    expect(id, isNotNull);
    expect(api.uploadedIds, [id]);

    vm.acknowledge();
    await settle();
    expect(sub.read().status, RecorderStatus.idle);
    expect(sub.read().finishedRunId, isNull);
  });

  test('pause and resume reach the repository', () async {
    final sub = container.listen(runViewModelProvider, (previous, next) {});
    final vm = container.read(runViewModelProvider.notifier);
    await vm.start();
    await vm.pause();
    await settle();
    expect(sub.read().status, RecorderStatus.paused);
    await vm.resume();
    await settle();
    expect(sub.read().status, RecorderStatus.recording);
    await vm.stop();
  });
}
