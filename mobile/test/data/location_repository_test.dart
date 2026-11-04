import 'package:flutter_test/flutter_test.dart';
import 'package:looprun/data/repositories/location_repository.dart';

import '../fakes/fakes.dart';

void main() {
  test('currentPositionOrNull never prompts and returns null without permission', () async {
    final permissions = FakePermissionService()..granted = false;
    final repo = LocationRepository(location: FakeLocationService(), permissions: permissions);
    expect(await repo.currentPositionOrNull(), isNull);
    expect(permissions.requests, 0);
  });

  test('currentPositionOrNull returns the fix when permitted', () async {
    final repo = LocationRepository(
      location: FakeLocationService(),
      permissions: FakePermissionService(),
    );
    final fix = await repo.currentPositionOrNull();
    expect(fix!.lat, 50.0);
  });

  test('requestPermission goes to the permission service', () async {
    final permissions = FakePermissionService();
    final repo = LocationRepository(location: FakeLocationService(), permissions: permissions);
    expect(await repo.requestPermission(), isTrue);
    expect(permissions.requests, 1);
  });
}
