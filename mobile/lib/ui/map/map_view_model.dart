import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/api_exception.dart';
import '../../data/models/models.dart';
import '../../data/providers.dart';
import '../../data/repositories/cell_repository.dart';
import '../../domain/recorder/run_recorder.dart';

/// Cells are only requested at this zoom or closer.
const double minZoomForCells = 12.5;

/// The server rejects boxes larger than 0.2 degrees on a side.
const double maxBboxSideDeg = 0.19;

/// "minLng,minLat,maxLng,maxLat" for the visible area, shrunk around its centre to the server limit.
String computeBbox({
  required double south,
  required double west,
  required double north,
  required double east,
}) {
  final centerLat = (south + north) / 2;
  final centerLng = (west + east) / 2;
  final halfLat = math.min((north - south) / 2, maxBboxSideDeg / 2);
  final halfLng = math.min((east - west) / 2, maxBboxSideDeg / 2);
  return '${centerLng - halfLng},${centerLat - halfLat},${centerLng + halfLng},${centerLat + halfLat}';
}

class MapState {
  const MapState({
    this.cells = const [],
    this.notice = zoomInNotice,
    this.loading = false,
    this.loadFailed = false,
    this.offline = false,
  });

  static const String zoomInNotice = 'Zoom in to see claimed cells';
  static const String emptyNotice = 'No claimed cells here yet. Be the first.';

  final List<Cell> cells;

  /// Text about the map itself (zoomed out, nothing here, load failed), or null.
  final String? notice;

  /// The first load of the visible area is running.
  final bool loading;

  /// The last load failed; [notice] says why and the screen offers "Try again".
  final bool loadFailed;

  /// The last load got no answer from the server at all.
  final bool offline;

  /// Own cells in view that have lost more than half of their hold. The server sends the strength
  /// only for the caller's own cells; nothing is estimated on the phone.
  int get fadingCount {
    var n = 0;
    for (final c in cells) {
      if (c.isFading) n++;
    }
    return n;
  }

  MapState copyWith({
    List<Cell>? cells,
    String? notice,
    bool clearNotice = false,
    bool? loading,
    bool? loadFailed,
    bool? offline,
  }) {
    return MapState(
      cells: cells ?? this.cells,
      notice: clearNotice ? null : (notice ?? this.notice),
      loading: loading ?? this.loading,
      loadFailed: loadFailed ?? this.loadFailed,
      offline: offline ?? this.offline,
    );
  }
}

class _Area {
  const _Area(this.south, this.west, this.north, this.east);
  final double south;
  final double west;
  final double north;
  final double east;
}

/// View model of the map. The server owns ownership; this only asks the repository for the visible area
/// and keeps the live socket pointed at it. Leaving the map (auto dispose) closes the socket.
class MapViewModel extends AutoDisposeNotifier<MapState> {
  bool _loading = false;
  bool _alive = true;
  _Area? _queued;
  _Area? _lastArea;

  CellRepository get _cells => ref.read(cellRepositoryProvider);

  @override
  MapState build() {
    final repo = ref.watch(cellRepositoryProvider);
    final sub = repo.updates.listen((cells) {
      state = state.copyWith(cells: cells);
    });
    ref.onDispose(() {
      _alive = false;
      sub.cancel();
      repo.stopLive();
    });
    return const MapState();
  }

  /// The camera is zoomed out too far: no cells, no socket.
  void onZoomedOut() {
    _queued = null;
    _lastArea = null;
    _cells.stopLive();
    _cells.clear();
    state = const MapState();
  }

  /// The camera stopped moving over this area (zoom is at least [minZoomForCells]).
  Future<void> onCameraIdle({
    required double south,
    required double west,
    required double north,
    required double east,
  }) async {
    final area = _Area(south, west, north, east);
    if (_loading) {
      _queued = area; // run the newest request when the current one finishes
      return;
    }
    _loading = true;
    try {
      var next = area;
      while (true) {
        await _load(next);
        final queued = _queued;
        if (queued == null) break;
        _queued = null;
        next = queued;
      }
    } finally {
      _loading = false;
    }
  }

  Future<void> _load(_Area a) async {
    _lastArea = a;
    if (_alive && state.cells.isEmpty) state = state.copyWith(loading: true);
    try {
      final bbox = computeBbox(south: a.south, west: a.west, north: a.north, east: a.east);
      final cells = await _cells.loadArea(bbox);
      if (!_alive) return;
      _cells.startLive(bbox);
      state = cells.isEmpty
          ? state.copyWith(notice: MapState.emptyNotice, loading: false, loadFailed: false, offline: false)
          : state.copyWith(clearNotice: true, loading: false, loadFailed: false, offline: false);
    } on ApiException catch (e) {
      if (_alive) {
        state = state.copyWith(
          notice: e.isNetwork ? 'Could not load cells. ${e.message}' : 'Could not load cells: ${e.message}',
          loading: false,
          loadFailed: true,
          offline: e.isNetwork,
        );
      }
    } catch (_) {
      if (_alive) state = state.copyWith(notice: 'Could not load cells', loading: false, loadFailed: true);
    }
  }

  /// "Try again" after a failed load: asks for the same area once more.
  Future<void> retry() async {
    final a = _lastArea;
    if (a == null) return;
    await onCameraIdle(south: a.south, west: a.west, north: a.north, east: a.east);
  }

  /// The claimed cell near a tapped point, or null.
  Cell? cellAt(double lat, double lng) => _cells.nearestCell(lat, lng);

  /// Where the phone is now, if permission is already granted. Never prompts.
  Future<GeoFix?> myPosition() => ref.read(locationRepositoryProvider).currentPositionOrNull();

  /// Returns the message to show the user.
  Future<String> reportCell(String cellId, String reason) async {
    try {
      await _cells.reportCell(cellId, reason);
      return 'Report sent. Thank you.';
    } on ApiException catch (e) {
      return e.statusCode == 429
          ? 'You have sent too many reports. Try again later.'
          : 'Could not send the report: ${e.message}';
    } catch (e) {
      return 'Could not send the report: $e';
    }
  }
}

final mapViewModelProvider =
    NotifierProvider.autoDispose<MapViewModel, MapState>(MapViewModel.new);
