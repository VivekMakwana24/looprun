import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import '../../core/config.dart';
import '../../core/theme.dart';
import '../../data/models/models.dart';
import '../core/report_dialog.dart';
import '../leaderboard/leaderboard_sheet.dart';
import 'map_view_model.dart';

class MapScreen extends ConsumerStatefulWidget {
  const MapScreen({super.key});

  @override
  ConsumerState<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends ConsumerState<MapScreen> {
  MapLibreMapController? _controller;

  // Drawing is serialised: the newest list wins, and two redraws never interleave.
  List<Cell> _latest = const [];
  bool _drawing = false;
  bool _dirty = false;

  Future<void> _onMapCreated(MapLibreMapController c) async {
    _controller = c;
    final me = await ref.read(mapViewModelProvider.notifier).myPosition();
    if (me == null || !mounted) return;
    try {
      await c.animateCamera(CameraUpdate.newLatLngZoom(LatLng(me.lat, me.lng), 14.5));
    } catch (_) {
      // The map may be gone already.
    }
  }

  Future<void> _onCameraIdle() async {
    final c = _controller;
    if (c == null) return;
    final vm = ref.read(mapViewModelProvider.notifier);
    final zoom = c.cameraPosition?.zoom ?? 0;
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

  Future<void> _draw(List<Cell> cells) async {
    _latest = cells;
    _dirty = true;
    if (_drawing) return;
    _drawing = true;
    try {
      while (_dirty) {
        _dirty = false;
        final c = _controller;
        if (c == null) break;
        final options = <CircleOptions>[];
        for (final cell in _latest) {
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
      }
    } catch (_) {
      // Drawing failed (map disposed); the next change draws again.
    } finally {
      _drawing = false;
    }
  }

  Future<void> _onMapClick(math.Point<double> point, LatLng latLng) async {
    final cell = ref.read(mapViewModelProvider.notifier).cellAt(latLng.latitude, latLng.longitude);
    if (cell == null || !mounted) return;
    final String who;
    if (cell.mine) {
      who = 'This cell is yours.';
    } else if (cell.hidden || cell.owner == null) {
      who = 'The owner of this cell is private.';
    } else {
      who = 'Held by ${cell.owner!.name}.';
    }
    final report = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cell'),
        content: Text(who),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Close')),
          TextButton(
            key: const Key('report_cell_button'),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Report this cell'),
          ),
        ],
      ),
    );
    if (report != true || !mounted) return;
    final reason = await askReportReason(context, title: 'Report this cell');
    if (reason == null || !mounted) return;
    final message = await ref.read(mapViewModelProvider.notifier).reportCell(cell.id, reason);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<List<Cell>>(mapViewModelProvider.select((s) => s.cells), (previous, next) {
      _draw(next);
    });
    final notice = ref.watch(mapViewModelProvider.select((s) => s.notice));
    return Stack(
      children: [
        MapLibreMap(
          styleString: AppConfig.mapStyleUrl,
          initialCameraPosition: const CameraPosition(target: LatLng(50.0, 8.7), zoom: 13),
          onMapCreated: _onMapCreated,
          onStyleLoadedCallback: _onCameraIdle,
          onCameraIdle: _onCameraIdle,
          onMapClick: _onMapClick,
          featureTapsTriggersMapClick: true,
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
        if (notice != null)
          Positioned(
            left: 12,
            right: 12,
            bottom: 12,
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(notice, textAlign: TextAlign.center),
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
            dot(mineColor, 'Mine'),
            dot(othersColor, 'Others'),
            dot(hiddenColor, 'Private'),
          ],
        ),
      ),
    );
  }
}
