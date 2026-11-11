import 'package:geolocator/geolocator.dart';

import '../../domain/recorder/run_recorder.dart';

/// Reads the device position. Permission prompts are not part of it (see `PermissionService`).
abstract class LocationService {
  /// Whether the device location switch is on.
  Future<bool> isEnabled();

  /// Continuous fixes, roughly one per second. Cancel the subscription to stop GPS.
  Stream<GeoFix> fixes();

  /// One high-accuracy fix.
  Future<GeoFix> currentPosition();
}

class GeolocatorLocationService implements LocationService {
  GeoFix _toFix(Position p) => GeoFix(
        lat: p.latitude,
        lng: p.longitude,
        t: p.timestamp.millisecondsSinceEpoch,
        acc: p.accuracy,
        isMock: p.isMocked,
      );

  @override
  Future<bool> isEnabled() => Geolocator.isLocationServiceEnabled();

  @override
  Stream<GeoFix> fixes() {
    return Geolocator.getPositionStream(
      locationSettings: AndroidSettings(
        accuracy: LocationAccuracy.best,
        distanceFilter: 0,
        intervalDuration: const Duration(seconds: 1),
      ),
    ).map(_toFix);
  }

  @override
  Future<GeoFix> currentPosition() async {
    final p = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
    );
    return _toFix(p);
  }
}
