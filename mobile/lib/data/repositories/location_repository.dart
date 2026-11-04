import '../../domain/recorder/run_recorder.dart';
import '../services/location_service.dart';
import '../services/permission_service.dart';

/// Permission and one-off position reads for the map and the disclosure screen.
/// (Recording has its own path through `RunRepository`.)
class LocationRepository {
  LocationRepository({required LocationService location, required PermissionService permissions})
      : _location = location,
        _permissions = permissions;

  final LocationService _location;
  final PermissionService _permissions;

  Future<bool> hasPermission() => _permissions.hasLocation();

  /// Shows the system prompt. Only call after the disclosure was accepted (or from its Agree button).
  Future<bool> requestPermission() => _permissions.requestLocation();

  /// One fix, or null if the permission is missing or no fix could be read.
  Future<GeoFix?> currentPositionOrNull() async {
    try {
      if (!await _permissions.hasLocation()) return null;
      return await _location.currentPosition();
    } catch (_) {
      return null;
    }
  }
}
