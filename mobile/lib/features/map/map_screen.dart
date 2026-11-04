import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart' as geo;
import 'package:maplibre_gl/maplibre_gl.dart';

import '../../core/config.dart';
import '../../core/providers.dart';
import '../../data/api/api_exception.dart';
import '../leaderboard/leaderboard_sheet.dart';

const double _minZoomForCells = 12.5;
const double _maxSideDeg = 0.19; // server limit is 0.2

class MapScreen extends ConsumerStatefulWidget {
  const MapScreen({super.key});

  @override
  ConsumerState<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends ConsumerState<MapScreen> {
  MapLibreMapController? _controller;
  String? _notice = 'Zoom in to see claimed cells';
  bool _loading = false;

  Future<void> _onMapCreated(MapLibreMapController c) async {
    _controller = c;
    await _centerOnMe();
  }

  Future<void> _centerOnMe() async {
    final c = _controller;
    if (c == null) return;
    try {
      if (!await ref.read(permissionGatewayProvider).hasLocation()) return;
      final p = await geo.Geolocator.getCurrentPosition(
        locationSettings: const geo.LocationSettings(accuracy: geo.LocationAccuracy.high),
      );
      await c.animateCamera(CameraUpdate.newLatLngZoom(LatLng(p.latitude, p.longitude), 14.5));
    } catch (_) {
      // No fix yet: stay on the default view.
    }
  }

  Future<void> _refreshCells() async {
    final c = _controller;
    if (c == null || _loading) return;
    final zoom = c.cameraPosition?.zoom ?? 0;
    if (zoom < _minZoomForCells) {
      await c.clearCircles();
      if (mounted) setState(() => _notice = 'Zoom in to see claimed cells');
      return;
    }
    _loading = true;
    try {
      final bounds = await c.getVisibleRegion();
      final centerLat = (bounds.southwest.latitude + bounds.northeast.latitude) / 2;
      final centerLng = (bounds.southwest.longitude + bounds.northeast.longitude) / 2;
      final halfLat = math.min((bounds.northeast.latitude - bounds.southwest.latitude) / 2, _maxSideDeg / 2);
      final halfLng = math.min((bounds.northeast.longitude - bounds.southwest.longitude) / 2, _maxSideDeg / 2);
      final bbox = '${centerLng - halfLng},${centerLat - halfLat},${centerLng + halfLng},${centerLat + halfLat}';

      final cells = await ref.read(apiClientProvider).getCells(bbox);
      final options = <CircleOptions>[];
      for (final cell in cells) {
        final lat = cell.lat, lng = cell.lng;
        if (lat == null || lng == null) continue;
        final String color;
        if (cell.mine) {
          color = '#1B8A5A';
        } else if (cell.hidden || cell.owner == null) {
          color = '#7A7A8C';
        } else {
          color = '#E5701B';
        }
        options.add(CircleOptions(
          geometry: LatLng(lat, lng),
          circleRadius: 7,
          circleColor: color,
          circleOpacity: 0.75,
          circleStrokeColor: '#ffffff',
          circleStrokeWidth: 1,
        ));
      }
      await c.clearCircles();
      if (options.isNotEmpty) await c.addCircles(options);
      if (mounted) {
        setState(() => _notice = cells.isEmpty ? 'No claimed cells here yet. Be the first.' : null);
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _notice = 'Could not load cells: ${e.message}');
    } catch (_) {
      if (mounted) setState(() => _notice = 'Could not load cells');
    } finally {
      _loading = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        MapLibreMap(
          styleString: AppConfig.mapStyleUrl,
          initialCameraPosition: const CameraPosition(target: LatLng(50.0, 8.7), zoom: 13),
          onMapCreated: _onMapCreated,
          onStyleLoadedCallback: _refreshCells,
          onCameraIdle: _refreshCells,
          trackCameraPosition: true,
          compassEnabled: true,
        ),
        Positioned(
          left: 12,
          top: 12,
          right: 12,
          child: Row(
            children: [
              const _Legend(),
              const Spacer(),
              FloatingActionButton.small(
                heroTag: 'leaderboard_fab',
                tooltip: 'Weekly leaderboard',
                onPressed: () => showLeaderboardSheet(context),
                child: const Icon(Icons.emoji_events_outlined),
              ),
            ],
          ),
        ),
        if (_notice != null)
          Positioned(
            left: 12,
            right: 12,
            bottom: 12,
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(_notice!, textAlign: TextAlign.center),
              ),
            ),
          ),
      ],
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend();

  @override
  Widget build(BuildContext context) {
    Widget dot(Color c, String label) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.circle, size: 12, color: c),
            const SizedBox(width: 4),
            Text(label, style: const TextStyle(fontSize: 12)),
            const SizedBox(width: 10),
          ],
        );
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 6, 0, 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            dot(const Color(0xFF1B8A5A), 'Mine'),
            dot(const Color(0xFFE5701B), 'Others'),
            dot(const Color(0xFF7A7A8C), 'Private'),
          ],
        ),
      ),
    );
  }
}
