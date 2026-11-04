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

  test('HomeZone equality is by value', () {
    expect(const HomeZone(lat: 1, lng: 2, radiusM: 3), const HomeZone(lat: 1, lng: 2, radiusM: 3));
  });
}
