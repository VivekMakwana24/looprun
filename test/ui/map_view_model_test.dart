import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:looprun/data/models/api_exception.dart';
import 'package:looprun/data/models/models.dart';
import 'package:looprun/data/providers.dart';
import 'package:looprun/data/services/token_store.dart';
import 'package:looprun/ui/map/map_view_model.dart';

import '../fakes/fakes.dart';

void main() {
  group('computeBbox', () {
    test('keeps a small box as it is', () {
      final parts = computeBbox(south: 50.0, west: 8.0, north: 50.1, east: 8.1).split(',');
      expect(double.parse(parts[0]), closeTo(8.0, 1e-9));
      expect(double.parse(parts[1]), closeTo(50.0, 1e-9));
      expect(double.parse(parts[2]), closeTo(8.1, 1e-9));
      expect(double.parse(parts[3]), closeTo(50.1, 1e-9));
    });

    test('shrinks a big box around its centre to the server limit', () {
      final parts = computeBbox(south: 49.0, west: 8.0, north: 51.0, east: 10.0).split(',');
      final w = double.parse(parts[2]) - double.parse(parts[0]);
      final h = double.parse(parts[3]) - double.parse(parts[1]);
      expect(w, closeTo(maxBboxSideDeg, 1e-9));
      expect(h, closeTo(maxBboxSideDeg, 1e-9));
      expect((double.parse(parts[0]) + double.parse(parts[2])) / 2, closeTo(9.0, 1e-9));
    });
  });

  group('MapViewModel', () {
    late FakeApiService api;
    late FakeLiveService live;
    late ProviderContainer container;

    setUp(() {
      api = FakeApiService()
        ..cells = [
          const Cell(id: 'a', lat: 50.05, lng: 8.05, owner: UserRef(id: 'u2', name: 'bob')),
        ];
      live = FakeLiveService();
      container = ProviderContainer(overrides: [
        apiServiceProvider.overrideWithValue(api),
        liveServiceProvider.overrideWithValue(live),
        locationServiceProvider.overrideWithValue(FakeLocationService()),
        permissionServiceProvider.overrideWithValue(FakePermissionService()),
        tokenStoreProvider.overrideWithValue(InMemoryTokenStore(
          const StoredSession(token: 'tok', userId: 'u1', userName: 'dev'),
        )),
        googleAuthServiceProvider.overrideWithValue(FakeGoogleAuthService()),
      ]);
    });

    tearDown(() => container.dispose());

    test('onCameraIdle loads cells, clears the zoom notice and starts the live socket', () async {
      final sub = container.listen(mapViewModelProvider, (previous, next) {});
      await container.read(authRepositoryProvider).restore();
      expect(sub.read().notice, MapState.zoomInNotice);

      await container
          .read(mapViewModelProvider.notifier)
          .onCameraIdle(south: 50.0, west: 8.0, north: 50.1, east: 8.1);
      await settle();

      expect(api.bboxes.length, 1);
      expect(sub.read().cells.single.id, 'a');
      expect(sub.read().notice, isNull);
      expect(live.sockets.length, 1);
      expect(live.tokens.single, 'tok');
    });

    test('an empty area says so; an API error is shown', () async {
      final sub = container.listen(mapViewModelProvider, (previous, next) {});
      api.cells = [];
      await container
          .read(mapViewModelProvider.notifier)
          .onCameraIdle(south: 50.0, west: 8.0, north: 50.1, east: 8.1);
      expect(sub.read().notice, contains('No claimed cells'));

      api.cellsError = const ApiException(429, 'slow');
      await container
          .read(mapViewModelProvider.notifier)
          .onCameraIdle(south: 50.0, west: 8.0, north: 50.1, east: 8.1);
      expect(sub.read().notice, contains('slow'));
    });

    test('zooming out clears cells and closes the socket', () async {
      final sub = container.listen(mapViewModelProvider, (previous, next) {});
      await container.read(authRepositoryProvider).restore();
      final vm = container.read(mapViewModelProvider.notifier);
      await vm.onCameraIdle(south: 50.0, west: 8.0, north: 50.1, east: 8.1);
      expect(live.latest.hasListener, isTrue, reason: 'the socket is open while the map shows cells');
      vm.onZoomedOut();
      await settle();
      expect(live.latest.hasListener, isFalse, reason: 'zooming out must cancel the socket subscription');
      expect(sub.read().cells, isEmpty);
      expect(sub.read().notice, MapState.zoomInNotice);
    });

    test('reportCell reports the message to show', () async {
      container.listen(mapViewModelProvider, (previous, next) {});
      final vm = container.read(mapViewModelProvider.notifier);
      expect(await vm.reportCell('a', 'fake'), contains('Report sent'));
      expect(api.reports.single['kind'], 'cell');
      api.reportError = const ApiException(429, 'x');
      expect(await vm.reportCell('a', 'fake'), contains('too many'));
    });
  });
}
