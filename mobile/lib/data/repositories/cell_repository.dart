import 'dart:async';

import '../../domain/recorder/geo.dart';
import '../models/models.dart';
import '../services/api_service.dart';
import '../services/live_service.dart';
import '../upload/backoff.dart';

/// The server decides who owns which cell; this repository only caches what the server said about the
/// area on screen. REST (GET /cells) loads it, the /live WebSocket keeps it fresh. Never decides ownership.
class CellRepository {
  CellRepository({
    required ApiService api,
    required LiveService live,
    required String? Function() tokenProvider,
    this.reconnectPolicy = const BackoffPolicy(base: Duration(seconds: 3), max: Duration(minutes: 2)),
  })  : _api = api,
        _live = live,
        _tokenProvider = tokenProvider;

  final ApiService _api;
  final LiveService _live;
  final String? Function() _tokenProvider;
  final BackoffPolicy reconnectPolicy;

  final Map<String, Cell> _cells = {};
  final StreamController<List<Cell>> _updates = StreamController<List<Cell>>.broadcast();

  StreamSubscription<CellChange>? _liveSub;
  Timer? _reconnectTimer;
  String? _liveBbox;
  int _reconnectFailures = 0;
  bool _disposed = false;

  /// Cells of the area last loaded, with live changes applied.
  List<Cell> get snapshot => List<Cell>.unmodifiable(_cells.values);

  /// Emits a new list whenever the cache changes.
  Stream<List<Cell>> get updates => _updates.stream;

  /// Whether the live socket is wanted (it may be between reconnects).
  bool get liveWanted => _liveBbox != null;

  void _publish() {
    if (!_updates.isClosed) _updates.add(snapshot);
  }

  /// Replaces the cache with the cells inside [bbox] ("minLng,minLat,maxLng,maxLat") from the server.
  /// Throws ApiException on failure; the old cache is kept then.
  Future<List<Cell>> loadArea(String bbox) async {
    final cells = await _api.getCells(bbox);
    _cells
      ..clear()
      ..addEntries(cells.map((c) => MapEntry(c.id, c)));
    _publish();
    return snapshot;
  }

  /// Forgets the cache (the map is zoomed out too far to show cells).
  void clear() {
    _cells.clear();
    _publish();
  }

  /// The cached cell whose centre is closest to the point, if within [maxMeters].
  Cell? nearestCell(double lat, double lng, {double maxMeters = 45}) {
    Cell? best;
    var bestDistance = maxMeters;
    for (final c in _cells.values) {
      final cl = c.lat, cg = c.lng;
      if (cl == null || cg == null) continue;
      final d = haversineM(lat, lng, cl, cg);
      if (d <= bestDistance) {
        best = c;
        bestDistance = d;
      }
    }
    return best;
  }

  Future<Leaderboard> weeklyLeaderboard() => _api.weeklyLeaderboard();

  Future<void> reportCell(String cellId, String reason) {
    return _api.report(kind: 'cell', targetId: cellId, reason: reason);
  }

  // ------------------------------------------------------------------ live

  /// Listens for ownership changes inside [bbox]. Calling it again with another box reconnects.
  /// Reconnects with backoff after a drop; gives up on an auth failure (4401).
  void startLive(String bbox) {
    if (_disposed) return;
    if (_liveBbox == bbox && (_liveSub != null || _reconnectTimer != null)) return;
    _liveBbox = bbox;
    _reconnectFailures = 0;
    _connect();
  }

  void stopLive() {
    _liveBbox = null;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    final sub = _liveSub;
    _liveSub = null;
    if (sub != null) unawaited(sub.cancel());
  }

  void _connect() {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    final old = _liveSub;
    _liveSub = null;
    if (old != null) unawaited(old.cancel());
    final bbox = _liveBbox;
    final token = _tokenProvider();
    if (bbox == null || token == null || token.isEmpty) return;
    late final StreamSubscription<CellChange> sub;
    sub = _live.connect(bbox: bbox, token: token).listen(
      (change) {
        _reconnectFailures = 0;
        _apply(change);
      },
      onError: (Object error) {
        if (!identical(_liveSub, sub)) return;
        _liveSub = null;
        if (error is LiveClosedException && error.isAuthFailure) {
          // The token is no good; retrying would not help. A REST call will notice the 401.
          _liveBbox = null;
          return;
        }
        _scheduleReconnect();
      },
      onDone: () {
        if (!identical(_liveSub, sub)) return;
        _liveSub = null;
        _scheduleReconnect();
      },
      cancelOnError: true,
    );
    _liveSub = sub;
  }

  void _scheduleReconnect() {
    if (_disposed || _liveBbox == null) return;
    _reconnectFailures++;
    final delay = reconnectPolicy.delayFor(_reconnectFailures);
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(delay, _connect);
  }

  void _apply(CellChange change) {
    _cells[change.id] = change.toCell();
    _publish();
  }

  Future<void> dispose() async {
    _disposed = true;
    stopLive();
    await _updates.close();
  }
}
