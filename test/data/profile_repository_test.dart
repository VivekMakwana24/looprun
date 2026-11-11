import 'package:flutter_test/flutter_test.dart';
import 'package:looprun/core/app_exception.dart';
import 'package:looprun/data/models/api_exception.dart';
import 'package:looprun/data/models/models.dart';
import 'package:looprun/data/repositories/profile_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../fakes/fakes.dart';

void main() {
  late SharedPreferences prefs;
  late FakeApiService api;
  late MemoryStore store;
  late FakeLocationService location;
  late FakePermissionService permissions;
  late ProfileRepository repo;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    api = FakeApiService();
    store = MemoryStore();
    location = FakeLocationService();
    permissions = FakePermissionService();
    repo = ProfileRepository(
      api: api,
      prefs: prefs,
      runs: store,
      location: location,
      permissions: permissions,
      currentUserId: () => store.userId,
    );
  });

  test('disclosure is not accepted until accepted, and stays accepted', () async {
    expect(repo.disclosureAccepted, isFalse);
    await repo.acceptDisclosure();
    expect(repo.disclosureAccepted, isTrue);
  });

  test('addZoneHere uploads the full list and keeps it on the phone', () async {
    final zones = await repo.addZoneHere(200);
    expect(zones.single.radiusM, 200);
    expect(zones.single.lat, 50.0);
    expect(api.zonePuts.single.length, 1);
    expect(repo.homeZones().single, zones.single);
    await repo.addZoneHere(500);
    expect(api.zonePuts.last.length, 2);
    expect(repo.homeZones().length, 2);
  });

  test('addZoneHere keeps local state when the server refuses', () async {
    api.zoneError = const ApiException(500, 'down');
    await expectLater(repo.addZoneHere(100), throwsA(anything));
    expect(repo.homeZones(), isEmpty);
  });

  test('addZoneHere needs location permission and respects the maximum', () async {
    permissions.granted = false;
    await expectLater(repo.addZoneHere(100), throwsA(isA<AppException>()));
    permissions.granted = true;
    for (var i = 0; i < maxHomeZones; i++) {
      await repo.addZoneHere(100);
    }
    await expectLater(repo.addZoneHere(100), throwsA(isA<AppException>()));
    expect(repo.homeZones().length, maxHomeZones);
  });

  test('clearZones empties both server and phone', () async {
    await repo.addZoneHere(100);
    await repo.clearZones();
    expect(api.zonePuts.last, isEmpty);
    expect(repo.homeZones(), isEmpty);
  });

  test('freeze passes through', () async {
    api.freezeUntil = 123;
    expect(await repo.setFreeze(7), 123);
    expect(api.freezeCalls, [7]);
  });

  test('deleteAccount wipes runs and zones on the phone', () async {
    await store.createRun('r', 1);
    await repo.addZoneHere(100);
    await repo.deleteAccount();
    expect(api.deleted, isTrue);
    expect(store.runIds, isEmpty);
    expect(repo.homeZones(), isEmpty);
  });

  test('home zones belong to the account: B does not see A\'s zones, A gets them back', () async {
    await repo.addZoneHere(100);
    expect(repo.homeZones().length, 1);

    store.userId = 'u2'; // sign out A, sign in B
    expect(repo.homeZones(), isEmpty);
    await repo.addZoneHere(50);
    expect(repo.homeZones().single.radiusM, 50);

    store.userId = 'u1';
    expect(repo.homeZones().single.radiusM, 100);
  });

  test('nobody signed in: no zones and none can be added', () async {
    store.userId = null;
    expect(repo.homeZones(), isEmpty);
    await expectLater(repo.addZoneHere(100), throwsA(isA<AppException>()));
  });

  test('the old shared zones key is dropped, not handed to whoever signs in next', () async {
    await prefs.setString(legacyHomeZonesPrefKey, '[{"lat":1,"lng":2,"radius_m":100}]');
    expect(repo.homeZones(), isEmpty);
    await Future<void>.delayed(Duration.zero);
    expect(prefs.containsKey(legacyHomeZonesPrefKey), isFalse);
  });

  test('deleting account A leaves account B\'s runs and zones alone', () async {
    await repo.addZoneHere(100);
    await store.createRun('a-run', 1);
    store.userId = 'u2';
    await repo.addZoneHere(50);
    await store.createRun('b-run', 1);

    store.userId = 'u1';
    await repo.deleteAccount();
    expect(store.runIds, isEmpty);
    expect(repo.homeZones(), isEmpty);

    store.userId = 'u2';
    expect(store.runIds, ['b-run']);
    expect(repo.homeZones().single.radiusM, 50);
  });

  test('HomeZone equality is by value', () {
    expect(const HomeZone(lat: 1, lng: 2, radiusM: 3), const HomeZone(lat: 1, lng: 2, radiusM: 3));
  });
}
