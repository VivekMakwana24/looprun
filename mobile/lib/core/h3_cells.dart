import 'package:h3_flutter/h3_flutter.dart';

class LatLngD {
  const LatLngD(this.lat, this.lng);
  final double lat;
  final double lng;
}

/// Converts an H3 index (hex string) to the centre of the cell.
abstract class CellLocator {
  LatLngD? centerOf(String h3Id);
}

/// Uses the h3_flutter package. The package API differs between versions
/// (cellToLatLng vs h3ToGeo, lng vs lon), so calls are made dynamically with fallbacks.
/// Any failure returns null and that cell is simply not drawn.
class H3FlutterCellLocator implements CellLocator {
  dynamic _h3;

  @override
  LatLngD? centerOf(String h3Id) {
    try {
      _h3 ??= H3Factory().load();
      final index = BigInt.parse(h3Id, radix: 16);
      dynamic c;
      try {
        c = _h3.cellToLatLng(index);
      } on NoSuchMethodError {
        c = _h3.h3ToGeo(index);
      }
      final lat = (c.lat as num).toDouble();
      final lng = _readLng(c);
      if (lng == null) return null;
      return LatLngD(lat, lng);
    } catch (_) {
      // Library failed to load (native binary) or the id is malformed.
      return null;
    }
  }

  double? _readLng(dynamic c) {
    try {
      return (c.lng as num).toDouble();
    } catch (_) {}
    try {
      return (c.lon as num).toDouble();
    } catch (_) {}
    return null;
  }
}
