import 'geo.dart';

enum RecorderStatus { idle, recording, paused, finished }

/// One GPS fix as seen by the recorder (independent of any plugin type).
class GeoFix {
  const GeoFix({
    required this.lat,
    required this.lng,
    required this.t,
    required this.acc,
    this.isMock = false,
  });
  final double lat;
  final double lng;
  final int t;
  final double acc;
  final bool isMock;
}

/// Pure Dart state machine for one run: idle -> recording <-> paused -> finished -> (reset) idle.
/// No Flutter imports, so it is unit testable. Illegal transitions throw [StateError].
class RunRecorder {
  RunRecorder({
    required int Function() nowMs,
    required String Function() newId,
    this.maxAccuracyForDistanceM = 50.0,
  })  : _nowMs = nowMs,
        _newId = newId;

  final int Function() _nowMs;
  final String Function() _newId;

  /// Fixes less accurate than this are stored but do not add to the on-screen distance.
  final double maxAccuracyForDistanceM;

  RecorderStatus _status = RecorderStatus.idle;
  String? _runId;
  int? _startedAt;
  int? _endedAt;
  int _activeMs = 0;
  int? _segmentStart;
  double _distanceM = 0;
  int _fixCount = 0;
  GeoFix? _last;

  RecorderStatus get status => _status;
  String? get runId => _runId;
  int? get startedAt => _startedAt;
  int? get endedAt => _endedAt;
  double get distanceM => _distanceM;
  int get fixCount => _fixCount;
  bool get isActive => _status == RecorderStatus.recording || _status == RecorderStatus.paused;

  /// Time spent recording (paused time excluded).
  int get elapsedMs {
    final seg = _segmentStart;
    if (_status == RecorderStatus.recording && seg != null) {
      return _activeMs + (_nowMs() - seg);
    }
    return _activeMs;
  }

  void start() {
    if (_status != RecorderStatus.idle) {
      throw StateError('Cannot start from $_status');
    }
    final now = _nowMs();
    _runId = _newId();
    _startedAt = now;
    _segmentStart = now;
    _status = RecorderStatus.recording;
  }

  void pause() {
    if (_status != RecorderStatus.recording) {
      throw StateError('Cannot pause from $_status');
    }
    _closeSegment();
    _status = RecorderStatus.paused;
  }

  void resume() {
    if (_status != RecorderStatus.paused) {
      throw StateError('Cannot resume from $_status');
    }
    _segmentStart = _nowMs();
    _last = null; // do not count the straight line across the pause
    _status = RecorderStatus.recording;
  }

  void finish() {
    if (!isActive) {
      throw StateError('Cannot finish from $_status');
    }
    if (_status == RecorderStatus.recording) _closeSegment();
    _endedAt = _nowMs();
    _status = RecorderStatus.finished;
  }

  /// finished -> idle (or idle -> idle). Not allowed while a run is active.
  void reset() {
    if (isActive) {
      throw StateError('Cannot reset from $_status');
    }
    _status = RecorderStatus.idle;
    _runId = null;
    _startedAt = null;
    _endedAt = null;
    _activeMs = 0;
    _segmentStart = null;
    _distanceM = 0;
    _fixCount = 0;
    _last = null;
  }

  /// Returns true when the fix belongs to the run (only while recording) and should be persisted.
  bool addFix(GeoFix fix) {
    if (_status != RecorderStatus.recording) return false;
    _fixCount++;
    if (fix.acc <= maxAccuracyForDistanceM) {
      final prev = _last;
      if (prev != null) {
        _distanceM += haversineM(prev.lat, prev.lng, fix.lat, fix.lng);
      }
      _last = fix;
    }
    return true;
  }

  void _closeSegment() {
    final seg = _segmentStart;
    if (seg != null) _activeMs += _nowMs() - seg;
    _segmentStart = null;
  }
}
