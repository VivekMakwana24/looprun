import 'dart:convert';

import '../../core/app_theme_id.dart';

import '../../data/models/models.dart';
import '../../data/models/social_models.dart';

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

/// The cells the caller lost ("take it back"): one polygon per cell with a boundary (GeoJSON wants
/// [longitude, latitude] and a closed ring). Cells without a boundary are left out; the map still moves to
/// them from the list.
Map<String, dynamic> lostCellsGeoJson(List<LostCell> cells) {
  final features = <Map<String, dynamic>>[];
  for (final cell in cells) {
    if (cell.boundary.length < 3) continue;
    final ring = <List<double>>[
      for (final p in cell.boundary) <double>[p.lng, p.lat],
      <double>[cell.boundary.first.lng, cell.boundary.first.lat],
    ];
    features.add(<String, dynamic>{
      'type': 'Feature',
      'properties': <String, dynamic>{'id': cell.cell, 'kind': 'lost'},
      'geometry': <String, dynamic>{
        'type': 'Polygon',
        'coordinates': <List<List<double>>>[ring],
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

/// The built-in MapLibre style, the fallback when the network style does not load: one background layer in
/// the theme's map colour. It has no sources, so nothing is requested from any map server.
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

/// OpenFreeMap styles (https://openfreemap.org, no API key). Names checked against
/// hyperknot/openfreemap (README, deploy script) and hyperknot/openfreemap-styles (README); see NOTES.md.
const String openFreeMapPositron = 'https://tiles.openfreemap.org/styles/positron';
const String openFreeMapLiberty = 'https://tiles.openfreemap.org/styles/liberty';
const String openFreeMapDark = 'https://tiles.openfreemap.org/styles/dark';

/// The network style for a theme when no MAP_STYLE_URL override is set: the light Positron for the light
/// theme (dawn), the dark style for every dark theme (night, tartan, trail).
String networkStyleFor(AppThemeId theme, {String override = ''}) {
  if (override.isNotEmpty) return override;
  return theme == AppThemeId.dawn ? openFreeMapPositron : openFreeMapDark;
}

/// The style to load: the network style for the theme (or the override), or, when it did not load
/// ([useFallback]), the built-in plain style in the given colour.
String mapStyleFor({
  required AppThemeId theme,
  required String styleUrl,
  required String backgroundHex,
  bool useFallback = false,
}) =>
    useFallback ? builtInMapStyle(backgroundHex) : networkStyleFor(theme, override: styleUrl);
