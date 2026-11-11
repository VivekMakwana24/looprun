import 'dart:math' as math;

const double earthRadiusM = 6371008.8;

double _rad(double deg) => deg * math.pi / 180.0;

/// Great-circle distance in metres.
double haversineM(double lat1, double lng1, double lat2, double lng2) {
  final dLat = _rad(lat2 - lat1);
  final dLng = _rad(lng2 - lng1);
  final a = math.pow(math.sin(dLat / 2), 2) +
      math.cos(_rad(lat1)) * math.cos(_rad(lat2)) * math.pow(math.sin(dLng / 2), 2);
  return 2 * earthRadiusM * math.asin(math.min(1.0, math.sqrt(a.toDouble())));
}

/// A point of the recorded path, for drawing.
class PathPoint {
  const PathPoint(this.lat, this.lng);
  final double lat;
  final double lng;
}
