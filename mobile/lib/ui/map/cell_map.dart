import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import '../../core/config.dart';
import '../../core/theme.dart';
import '../../data/models/models.dart';
import '../core/theme_view_model.dart';
import 'cell_geojson.dart';
import 'map_view_model.dart';

const String _cellSource = 'lr-cells';
const String _pointSource = 'lr-cell-points';
const String _meSource = 'lr-me';

/// The map itself: MapLibre with the cells as hexagons (fill layers on a GeoJSON source), coloured from
/// the active theme. Reads the cells from [mapViewModelProvider] and reports camera stops to it.
class CellMap extends ConsumerStatefulWidget {
  const CellMap({super.key, required this.recenter, required this.onCellTap, this.onNoPosition});

  /// Notified when the "centre on me" button is pressed.
  final Listenable recenter;
  final void Function(Cell cell) onCellTap;

  /// Called when "centre on me" could not read a position (no permission, location off).
  final VoidCallback? onNoPosition;

  @override
  ConsumerState<CellMap> createState() => _CellMapState();
}

class _CellMapState extends ConsumerState<CellMap> {
  MapLibreMapController? _controller;
  AppThemeId? _themeId;
  bool _layersReady = false;
  bool _centredOnce = false;

  /// maplibre_gl has no style-load error callback, so a style that has not loaded after this long is
  /// treated as failed and the built-in plain style is shown instead (until the next theme change).
  static const Duration _styleTimeout = Duration(seconds: 20);
  Timer? _styleTimer;
  bool _styleLoaded = false;
  bool _useFallback = false;

  /// Where the camera was, so a theme change (which rebuilds the map view) keeps the place.
  CameraPosition _camera = const CameraPosition(target: LatLng(50.0, 8.7), zoom: 13);

  /// The phone's position, read once when the map opens and on "centre on me" (never tracked).
  double? _meLat;
  double? _meLng;

  // Drawing is serialised: the newest list wins, and two redraws never interleave.
  List<Cell> _latest = const [];
  bool _drawing = false;
  bool _dirty = false;

  @override
  void initState() {
    super.initState();
    widget.recenter.addListener(_recenter);
  }

  @override
  void didUpdateWidget(covariant CellMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.recenter, widget.recenter)) {
      oldWidget.recenter.removeListener(_recenter);
      widget.recenter.addListener(_recenter);
    }
  }

  @override
  void dispose() {
    _styleTimer?.cancel();
    widget.recenter.removeListener(_recenter);
    super.dispose();
  }

  Future<void> _onMapCreated(MapLibreMapController c) async {
    _controller = c;
    if (_centredOnce) return;
    _centredOnce = true;
    await _moveToMe(c, tellWhenMissing: false);
  }

  Future<void> _recenter() async {
    final c = _controller;
    if (c == null) return;
    await _moveToMe(c, tellWhenMissing: true);
  }

  Future<void> _moveToMe(MapLibreMapController c, {required bool tellWhenMissing}) async {
    final me = await ref.read(mapViewModelProvider.notifier).myPosition();
    if (!mounted) return;
    if (me == null) {
      if (tellWhenMissing) widget.onNoPosition?.call();
      return;
    }
    _meLat = me.lat;
    _meLng = me.lng;
    try {
      await c.animateCamera(CameraUpdate.newLatLngZoom(LatLng(me.lat, me.lng), 14.5));
    } catch (_) {
      // The map may be gone already.
    }
    await _drawMe();
  }

  /// A style finished loading (first time, and again after a theme change): add our sources and layers.
  Future<void> _onStyleLoaded() async {
    final c = _controller;
    if (c == null || !mounted) return;
    _styleTimer?.cancel();
    _styleLoaded = true;
    final colors = context.lr;
    _layersReady = false;
    try {
      await c.addGeoJsonSource(_cellSource, emptyFeatureCollection);
      await c.addGeoJsonSource(_pointSource, emptyFeatureCollection);
      await c.addGeoJsonSource(_meSource, emptyFeatureCollection);

      final accent = hexOf(colors.accent);
      final rival = hexOf(colors.rival);
      final gap = hexOf(colors.map);

      // Hexagons. Order = drawing order: others, private, then yours on top.
      await c.addFillLayer(
        _cellSource,
        'lr-hex-rival',
        FillLayerProperties(fillColor: rival, fillOpacity: 0.88, fillOutlineColor: gap),
        filter: _kindIs(CellKind.rival),
      );
      await c.addFillLayer(
        _cellSource,
        'lr-hex-hidden',
        FillLayerProperties(fillColor: hexOf(colors.hidFill), fillOpacity: 0.9),
        filter: _kindIs(CellKind.hidden),
      );
      await c.addLineLayer(
        _cellSource,
        'lr-hex-hidden-line',
        LineLayerProperties(
          lineColor: hexOf(colors.hidLine),
          lineWidth: 1.5,
          lineDasharray: <double>[2.5, 2.5],
        ),
        filter: _kindIs(CellKind.hidden),
      );
      await c.addFillLayer(
        _cellSource,
        'lr-hex-fading',
        FillLayerProperties(fillColor: accent, fillOpacity: 0.4, fillOutlineColor: gap),
        filter: _kindIs(CellKind.fading),
      );
      await c.addFillLayer(
        _cellSource,
        'lr-hex-mine',
        FillLayerProperties(fillColor: accent, fillOpacity: 1.0, fillOutlineColor: gap),
        filter: _kindIs(CellKind.mine),
      );

      // Circles for cells that came without a boundary.
      await c.addCircleLayer(
        _pointSource,
        'lr-pt-rival',
        CircleLayerProperties(circleRadius: 7, circleColor: rival, circleOpacity: 0.88),
        filter: _kindIs(CellKind.rival),
      );
      await c.addCircleLayer(
        _pointSource,
        'lr-pt-hidden',
        CircleLayerProperties(
          circleRadius: 7,
          circleColor: hexOf(colors.hidFill),
          circleStrokeColor: hexOf(colors.hidLine),
          circleStrokeWidth: 1.5,
        ),
        filter: _kindIs(CellKind.hidden),
      );
      await c.addCircleLayer(
        _pointSource,
        'lr-pt-fading',
        CircleLayerProperties(circleRadius: 7, circleColor: accent, circleOpacity: 0.4),
        filter: _kindIs(CellKind.fading),
      );
      await c.addCircleLayer(
        _pointSource,
        'lr-pt-mine',
        CircleLayerProperties(circleRadius: 7, circleColor: accent, circleOpacity: 1.0),
        filter: _kindIs(CellKind.mine),
      );

      // Where the phone is: a dot with a ring.
      await c.addCircleLayer(
        _meSource,
        'lr-me-halo',
        CircleLayerProperties(circleRadius: 17, circleColor: hexOf(colors.dotRing), circleOpacity: 0.35),
      );
      await c.addCircleLayer(
        _meSource,
        'lr-me-dot',
        CircleLayerProperties(
          circleRadius: 8,
          circleColor: hexOf(colors.dot),
          circleStrokeColor: hexOf(colors.dotRing),
          circleStrokeWidth: 3,
        ),
      );
      _layersReady = true;
    } catch (_) {
      // The map went away while the layers were added; the next style load starts again.
      return;
    }
    await _drawMe();
    await _draw(ref.read(mapViewModelProvider).cells);
    await _onCameraIdle();
  }

  static List<Object> _kindIs(CellKind kind) => <Object>[
        '==',
        <Object>['get', 'kind'],
        kind.name,
      ];

  Future<void> _onCameraIdle() async {
    final c = _controller;
    if (c == null) return;
    final position = c.cameraPosition;
    if (position != null) _camera = position;
    final vm = ref.read(mapViewModelProvider.notifier);
    final zoom = position?.zoom ?? 0;
    if (zoom < minZoomForCells) {
      vm.onZoomedOut();
      return;
    }
    try {
      final bounds = await c.getVisibleRegion();
      await vm.onCameraIdle(
        south: bounds.southwest.latitude,
        west: bounds.southwest.longitude,
        north: bounds.northeast.latitude,
        east: bounds.northeast.longitude,
      );
    } catch (_) {
      // The next camera move tries again.
    }
  }

  Future<void> _drawMe() async {
    final c = _controller;
    if (c == null || !_layersReady) return;
    try {
      await c.setGeoJsonSource(_meSource, pointGeoJson(_meLat, _meLng));
    } catch (_) {}
  }

  /// One source update per change, whatever the number of cells (review F17).
  Future<void> _draw(List<Cell> cells) async {
    _latest = cells;
    _dirty = true;
    if (_drawing) return;
    _drawing = true;
    try {
      while (_dirty) {
        _dirty = false;
        final c = _controller;
        if (c == null || !_layersReady) break;
        final now = _latest;
        await c.setGeoJsonSource(_cellSource, cellPolygonsGeoJson(now));
        await c.setGeoJsonSource(_pointSource, cellPointsGeoJson(now));
      }
    } catch (_) {
      // Drawing failed (map disposed); the next change draws again.
    } finally {
      _drawing = false;
    }
  }

  void _onMapClick(math.Point<double> point, LatLng latLng) {
    final cell = ref.read(mapViewModelProvider.notifier).cellAt(latLng.latitude, latLng.longitude);
    if (cell != null) widget.onCellTap(cell);
  }

  @override
  Widget build(BuildContext context) {
    final themeId = ref.watch(themeViewModelProvider);
    final colors = context.lr;
    if (_themeId != themeId) {
      // Another theme: the map view below is rebuilt (new key) with the new style and layer colours.
      _camera = _controller?.cameraPosition ?? _camera;
      _controller = null;
      _layersReady = false;
      _themeId = themeId;
      _useFallback = false;
      _styleLoaded = false;
      _styleTimer?.cancel();
      _styleTimer = Timer(_styleTimeout, () {
        if (!mounted || _styleLoaded || _useFallback) return;
        // The network style never loaded: rebuild the map view with the built-in style.
        setState(() {
          _controller = null;
          _layersReady = false;
          _useFallback = true;
        });
      });
    }
    ref.listen<List<Cell>>(mapViewModelProvider.select((s) => s.cells), (previous, next) {
      _draw(next);
    });
    return MapLibreMap(
      key: ValueKey<String>('cell_map_${themeId.name}${_useFallback ? '_offline' : ''}'),
      styleString: mapStyleFor(
        theme: themeId,
        styleUrl: AppConfig.mapStyleUrl,
        backgroundHex: hexOf(colors.map),
        useFallback: _useFallback,
      ),
      initialCameraPosition: _camera,
      onMapCreated: _onMapCreated,
      onStyleLoadedCallback: _onStyleLoaded,
      onCameraIdle: _onCameraIdle,
      onMapClick: _onMapClick,
      featureTapsTriggersMapClick: true,
      trackCameraPosition: true,
      compassEnabled: false,
      // OpenFreeMap requires "OpenFreeMap (c) OpenMapTiles, data from OpenStreetMap": MapLibre's own
      // attribution (i) button carries it, so it stays on screen.
      attributionEnabled: true,
      attributionButtonPosition: AttributionButtonPosition.bottomRight,
    );
  }
}
