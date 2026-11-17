import 'dart:convert';

import '../../data/models/models.dart';

/// How a cell is drawn. The value is also the GeoJSON `kind` property the map layers filter on.
enum CellKind {
  /// Own cell with at least half of its hold left: solid accent.
  mine,

  /// Own cell with less than half of its hold left: accent at lower opacity.
  fading,

  /// Somebody else's cell, name visible: rival colour.
  rival,

  /// Owner hidden by the privacy rules: dashed outline.
  hidden,
}

CellKind cellKind(Cell cell) {
  if (cell.mine) return cell.isFading ? CellKind.fading : CellKind.mine;
  if (cell.hidden || cell.owner == null) return CellKind.hidden;
  return CellKind.rival;
}

Map<String, dynamic> _collection(List<Map<String, dynamic>> features) =>
    <String, dynamic>{'type': 'FeatureCollection', 'features': features};

const Map<String, dynamic> emptyFeatureCollection = <String, dynamic>{
  'type': 'FeatureCollection',
  'features': <Map<String, dynamic>>[],
};

/// Polygons for every cell the server sent a boundary for (contract D10). GeoJSON wants
/// [longitude, latitude] and a closed ring; the server sends [lat, lng] corners, not closed.
Map<String, dynamic> cellPolygonsGeoJson(List<Cell> cells) {
  final features = <Map<String, dynamic>>[];
  for (final cell in cells) {
    if (cell.boundary.length < 3) continue;
    final ring = <List<double>>[
      for (final p in cell.boundary) <double>[p.lng, p.lat],
      <double>[cell.boundary.first.lng, cell.boundary.first.lat],
    ];
    features.add(<String, dynamic>{
      'type': 'Feature',
      'properties': <String, dynamic>{'id': cell.id, 'kind': cellKind(cell).name},
      'geometry': <String, dynamic>{
        'type': 'Polygon',
        'coordinates': <List<List<double>>>[ring],
      },
    });
  }
  return _collection(features);
}

/// Fallback for cells without a boundary (an older server): a point at the centre, drawn as a circle.
/// Cells with neither boundary nor centre cannot be drawn and are left out.
Map<String, dynamic> cellPointsGeoJson(List<Cell> cells) {
  final features = <Map<String, dynamic>>[];
  for (final cell in cells) {
    if (cell.boundary.length >= 3) continue;
    final lat = cell.lat, lng = cell.lng;
    if (lat == null || lng == null) continue;
    features.add(<String, dynamic>{
      'type': 'Feature',
      'properties': <String, dynamic>{'id': cell.id, 'kind': cellKind(cell).name},
      'geometry': <String, dynamic>{
        'type': 'Point',
        'coordinates': <double>[lng, lat],
      },
    });
  }
  return _collection(features);
}

/// One point (the phone's position, read once), or an empty collection.
Map<String, dynamic> pointGeoJson(double? lat, double? lng) {
  if (lat == null || lng == null) return emptyFeatureCollection;
  return _collection([
    <String, dynamic>{
      'type': 'Feature',
      'properties': <String, dynamic>{},
      'geometry': <String, dynamic>{
        'type': 'Point',
        'coordinates': <double>[lng, lat],
      },
    },
  ]);
}

/// The built-in MapLibre style used when no MAP_STYLE_URL is configured: one background layer in the
/// theme's map colour. It has no sources, so nothing is requested from any map server.
String builtInMapStyle(String backgroundHex) {
  return jsonEncode(<String, dynamic>{
    'version': 8,
    'name': 'Looprun plain',
    'sources': <String, dynamic>{},
    'layers': <Map<String, dynamic>>[
      <String, dynamic>{
        'id': 'background',
        'type': 'background',
        'paint': <String, dynamic>{'background-color': backgroundHex},
      },
    ],
  });
}

/// The style to load: the configured URL, or the built-in plain style in the given colour.
String mapStyleFor({required String styleUrl, required String backgroundHex}) =>
    styleUrl.isEmpty ? builtInMapStyle(backgroundHex) : styleUrl;
