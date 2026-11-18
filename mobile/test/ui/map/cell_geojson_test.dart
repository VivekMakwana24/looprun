import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:looprun/core/app_theme_id.dart';
import 'package:looprun/data/models/models.dart';
import 'package:looprun/data/models/social_models.dart';
import 'package:looprun/ui/map/cell_geojson.dart';

const _hex = [
  LatLngPoint(50.001, 8.7),
  LatLngPoint(50.0005, 8.701),
  LatLngPoint(49.9995, 8.701),
  LatLngPoint(49.999, 8.7),
  LatLngPoint(49.9995, 8.699),
  LatLngPoint(50.0005, 8.699),
];

void main() {
  test('cellKind: yours, fading, others, private', () {
    expect(cellKind(const Cell(id: 'a', mine: true, strength: 0.9)), CellKind.mine);
    expect(cellKind(const Cell(id: 'a', mine: true)), CellKind.mine, reason: 'no strength = not fading');
    expect(cellKind(const Cell(id: 'a', mine: true, strength: 0.49)), CellKind.fading);
    expect(cellKind(const Cell(id: 'b', owner: UserRef(id: 'u2', name: 'Bob'))), CellKind.rival);
    expect(cellKind(const Cell(id: 'c', hidden: true)), CellKind.hidden);
    expect(cellKind(const Cell(id: 'd')), CellKind.hidden, reason: 'no owner shown = private');
  });

  test('the kind names are the ones the map layer filters use', () {
    expect(CellKind.values.map((k) => k.name), ['mine', 'fading', 'rival', 'hidden']);
  });

  test('polygons are closed rings of [lng, lat] with the kind as a property', () {
    final fc = cellPolygonsGeoJson(const [Cell(id: 'a', boundary: _hex, mine: true, strength: 0.2)]);
    expect(fc['type'], 'FeatureCollection');
    final f = (fc['features'] as List).single as Map<String, dynamic>;
    expect(f['properties'], {'id': 'a', 'kind': 'fading'});
    final ring = ((f['geometry'] as Map)['coordinates'] as List).single as List;
    expect(ring.length, 7);
    expect(ring.first, [8.7, 50.001], reason: 'GeoJSON order is longitude, latitude');
    expect(ring.last, ring.first, reason: 'the ring is closed');
    // A JSON round trip keeps it (it is sent to the map as JSON).
    expect(jsonDecode(jsonEncode(fc)), fc);
  });

  test('cells without a boundary become points at the centre, cells with neither are skipped', () {
    const cells = [
      Cell(id: 'a', boundary: _hex, owner: UserRef(id: 'u2', name: 'Bob')),
      Cell(id: 'b', lat: 50.0, lng: 8.7, owner: UserRef(id: 'u2', name: 'Bob')),
      Cell(id: 'c', boundary: [LatLngPoint(1, 2), LatLngPoint(3, 4)], lat: 1.0, lng: 2.0, hidden: true),
      Cell(id: 'd'),
    ];
    final polys = cellPolygonsGeoJson(cells)['features'] as List;
    final points = cellPointsGeoJson(cells)['features'] as List;
    expect(polys.map((f) => (f as Map)['properties']['id']), ['a']);
    expect(points.map((f) => (f as Map)['properties']['id']), ['b', 'c']);
    final p = points.first as Map;
    expect(p['geometry'], {'type': 'Point', 'coordinates': [8.7, 50.0]});
    expect((points.last as Map)['properties']['kind'], 'hidden');
  });

  test('the phone position is one point, or nothing', () {
    expect(pointGeoJson(null, 8.7)['features'], isEmpty);
    final f = (pointGeoJson(50.0, 8.7)['features'] as List).single as Map;
    expect(f['geometry'], {'type': 'Point', 'coordinates': [8.7, 50.0]});
  });

  test('the built-in style loads nothing from anywhere', () {
    final style = jsonDecode(builtInMapStyle('#0D100E')) as Map<String, dynamic>;
    expect(style['version'], 8);
    expect(style['sources'], isEmpty);
    expect(style.containsKey('glyphs'), isFalse);
    expect(style.containsKey('sprite'), isFalse);
    final layers = style['layers'] as List;
    expect(layers.length, 1);
    expect(layers.single['type'], 'background');
    expect(layers.single['paint'], {'background-color': '#0D100E'});
    expect(builtInMapStyle('#000000'), isNot(contains('http')));
  });

  group('style choice', () {
    test('dawn gets Positron, every dark theme gets the dark style', () {
      expect(networkStyleFor(AppThemeId.dawn), 'https://tiles.openfreemap.org/styles/positron');
      for (final t in [AppThemeId.night, AppThemeId.tartan, AppThemeId.trail]) {
        expect(networkStyleFor(t), 'https://tiles.openfreemap.org/styles/dark', reason: t.name);
      }
    });

    test('MAP_STYLE_URL overrides the choice for every theme', () {
      for (final t in AppThemeId.values) {
        expect(networkStyleFor(t, override: 'https://tiles.example/style.json'), 'https://tiles.example/style.json');
      }
    });

    test('mapStyleFor returns the network style, or the built-in one as the fallback', () {
      expect(mapStyleFor(theme: AppThemeId.night, styleUrl: '', backgroundHex: '#000000'), openFreeMapDark);
      expect(mapStyleFor(theme: AppThemeId.dawn, styleUrl: '', backgroundHex: '#000000'), openFreeMapPositron);
      expect(mapStyleFor(theme: AppThemeId.dawn, styleUrl: 'https://x.example/s', backgroundHex: '#000000'),
          'https://x.example/s');
      final fallback = mapStyleFor(theme: AppThemeId.night, styleUrl: '', backgroundHex: '#123456', useFallback: true);
      expect(fallback, startsWith('{'));
      expect(fallback, isNot(contains('http')));
    });
  });

  test('lost cells ("take it back") are closed [lng, lat] rings; cells without a boundary are left out', () {
    final fc = lostCellsGeoJson(const [
      LostCell(cell: 'a', boundary: _hex, lostAt: 5),
      LostCell(cell: 'b', lat: 50.0, lng: 8.7),
    ]);
    final features = fc['features'] as List;
    expect(features.length, 1);
    final f = features.single as Map<String, dynamic>;
    expect(f['properties'], {'id': 'a', 'kind': 'lost'});
    final ring = ((f['geometry'] as Map)['coordinates'] as List).single as List;
    expect(ring.length, 7);
    expect(ring.first, [8.7, 50.001]);
    expect(ring.last, ring.first);
    expect(jsonDecode(jsonEncode(fc)), fc);
    expect(lostCellsGeoJson(const []), emptyFeatureCollection);
  });
}
