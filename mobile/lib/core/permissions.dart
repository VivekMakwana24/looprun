import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

/// Wraps runtime permission prompts so screens (and tests) never talk to plugins directly.
abstract class PermissionGateway {
  /// True when foreground location permission is already granted. Never prompts.
  Future<bool> hasLocation();

  /// Prompts for foreground location (and notifications) if needed. Returns true when location is granted.
  /// Must only be called after the disclosure screen was accepted.
  Future<bool> requestLocation();
}

class DevicePermissionGateway implements PermissionGateway {
  @override
  Future<bool> hasLocation() async {
    final p = await Geolocator.checkPermission();
    return p == LocationPermission.always || p == LocationPermission.whileInUse;
  }

  @override
  Future<bool> requestLocation() async {
    var p = await Geolocator.checkPermission();
    if (p == LocationPermission.denied) {
      p = await Geolocator.requestPermission();
    }
    final granted = p == LocationPermission.always || p == LocationPermission.whileInUse;
    if (granted) {
      try {
        await Permission.notification.request();
      } catch (_) {
        // Notification permission is best effort; the service still runs without it.
      }
    }
    return granted;
  }
}
