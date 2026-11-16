// Plain Dart models for docs/CONTRACT.openapi.yaml. No Flutter imports.

double? _d(Object? v) => v is num ? v.toDouble() : null;
int? _i(Object? v) => v is num ? v.toInt() : null;

class UserRef {
  const UserRef({required this.id, required this.name});
  final String id;
  final String name;

  factory UserRef.fromJson(Map<String, dynamic> j) =>
      UserRef(id: (j['id'] ?? '').toString(), name: (j['name'] ?? '').toString());

  Map<String, dynamic> toJson() => {'id': id, 'name': name};

  @override
  bool operator ==(Object other) => other is UserRef && other.id == id && other.name == name;

  @override
  int get hashCode => Object.hash(id, name);
}

class Session {
  const Session({required this.accessToken, required this.user});
  final String accessToken;
  final UserRef user;

  factory Session.fromJson(Map<String, dynamic> j) => Session(
        accessToken: j['access_token'] as String,
        user: UserRef.fromJson((j['user'] as Map).cast<String, dynamic>()),
      );
}

class Fix {
  const Fix({
    required this.lat,
    required this.lng,
    required this.t,
    required this.acc,
    this.mock = false,
  });
  final double lat;
  final double lng;
  final int t;
  final double acc;
  final bool mock;

  Map<String, dynamic> toJson() =>
      {'lat': lat, 'lng': lng, 't': t, 'acc': acc, 'mock': mock};
}

class RunUpload {
  const RunUpload({
    required this.id,
    required this.startedAt,
    required this.endedAt,
    required this.fixes,
    this.integrityToken,
  });
  final String id;
  final int startedAt;
  final int endedAt;
  final String? integrityToken;
  final List<Fix> fixes;

  Map<String, dynamic> toJson() => {
        'id': id,
        'started_at': startedAt,
        'ended_at': endedAt,
        'integrity_token': integrityToken,
        'fixes': fixes.map((f) => f.toJson()).toList(),
      };
}

class Flag {
  const Flag({required this.code, required this.severity, required this.detail});
  final String code;
  final String severity;
  final String detail;

  bool get isHard => severity == 'hard';

  factory Flag.fromJson(Map<String, dynamic> j) => Flag(
        code: (j['code'] ?? '').toString(),
        severity: (j['severity'] ?? 'soft').toString(),
        detail: (j['detail'] ?? '').toString(),
      );

  Map<String, dynamic> toJson() => {'code': code, 'severity': severity, 'detail': detail};
}

class LoopInfo {
  const LoopInfo({required this.cells, required this.areaKm2});
  final int cells;
  final double areaKm2;

  factory LoopInfo.fromJson(Map<String, dynamic> j) =>
      LoopInfo(cells: _i(j['cells']) ?? 0, areaKm2: _d(j['area_km2']) ?? 0);

  Map<String, dynamic> toJson() => {'cells': cells, 'area_km2': areaKm2};
}

class RunStatus {
  const RunStatus({
    required this.id,
    required this.status,
    this.distanceM,
    this.movingSeconds,
    this.loops = const [],
    this.cellsClaimed = 0,
    this.cellsTakenFromOthers = 0,
    this.flags = const [],
  });

  static const processing = 'processing';
  static const accepted = 'accepted';
  static const pendingReview = 'pending_review';
  static const rejected = 'rejected';

  final String id;
  final String status;
  final double? distanceM;
  final int? movingSeconds;
  final List<LoopInfo> loops;
  final int cellsClaimed;
  final int cellsTakenFromOthers;
  final List<Flag> flags;

  bool get isProcessing => status == processing;

  factory RunStatus.fromJson(Map<String, dynamic> j) {
    final loops = (j['loops'] as List?) ?? const [];
    final flags = (j['flags'] as List?) ?? const [];
    return RunStatus(
      id: (j['id'] ?? '').toString(),
      status: (j['status'] ?? processing).toString(),
      distanceM: _d(j['distance_m']),
      movingSeconds: _i(j['moving_seconds']),
      loops: loops.map((e) => LoopInfo.fromJson((e as Map).cast<String, dynamic>())).toList(),
      cellsClaimed: _i(j['cells_claimed']) ?? 0,
      cellsTakenFromOthers: _i(j['cells_taken_from_others']) ?? 0,
      flags: flags.map((e) => Flag.fromJson((e as Map).cast<String, dynamic>())).toList(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'status': status,
        'distance_m': distanceM,
        'moving_seconds': movingSeconds,
        'loops': loops.map((l) => l.toJson()).toList(),
        'cells_claimed': cellsClaimed,
        'cells_taken_from_others': cellsTakenFromOthers,
        'flags': flags.map((f) => f.toJson()).toList(),
      };
}

/// One corner of a cell's hexagon.
class LatLngPoint {
  const LatLngPoint(this.lat, this.lng);
  final double lat;
  final double lng;

  @override
  bool operator ==(Object other) => other is LatLngPoint && other.lat == lat && other.lng == lng;

  @override
  int get hashCode => Object.hash(lat, lng);
}

/// Parses `[[lat, lng], ...]` (contract D10). Anything malformed gives an empty list, and the map then
/// falls back to a circle at the cell centre.
List<LatLngPoint> _boundary(Object? v) {
  if (v is! List || v.length < 3) return const [];
  final out = <LatLngPoint>[];
  for (final e in v) {
    if (e is! List || e.length < 2) return const [];
    final lat = _d(e[0]);
    final lng = _d(e[1]);
    if (lat == null || lng == null) return const [];
    out.add(LatLngPoint(lat, lng));
  }
  return out;
}

class Cell {
  const Cell({
    required this.id,
    this.lat,
    this.lng,
    this.boundary = const [],
    this.owner,
    this.mine = false,
    this.hidden = false,
    this.strength,
  });
  final String id;

  /// Cell centre, computed by the server (decision D7).
  final double? lat;
  final double? lng;

  /// The hexagon corners in ring order, not closed (decision D10). Empty when the server did not send them.
  final List<LatLngPoint> boundary;
  final UserRef? owner;
  final bool mine;
  final bool hidden;

  /// 0..1, only for the caller's own cells (D10): how much of the hold is left. Null for everybody else.
  final double? strength;

  /// Below this an own cell is drawn as "fading".
  static const double fadingBelow = 0.5;

  /// True for an own cell that has lost more than half of its hold.
  bool get isFading {
    final s = strength;
    return mine && s != null && s < fadingBelow;
  }

  factory Cell.fromJson(Map<String, dynamic> j) {
    final o = j['owner'];
    final mine = j['mine'] == true;
    final s = _d(j['strength']);
    return Cell(
      id: (j['id'] ?? '').toString(),
      lat: _d(j['lat']),
      lng: _d(j['lng']),
      boundary: _boundary(j['boundary']),
      owner: o is Map ? UserRef.fromJson(o.cast<String, dynamic>()) : null,
      mine: mine,
      hidden: j['hidden'] == true,
      strength: mine && s != null ? s.clamp(0.0, 1.0).toDouble() : null,
    );
  }
}

class LeaderboardEntry {
  const LeaderboardEntry({required this.rank, required this.user, required this.cells});
  final int rank;
  final UserRef user;
  final int cells;

  factory LeaderboardEntry.fromJson(Map<String, dynamic> j) => LeaderboardEntry(
        rank: _i(j['rank']) ?? 0,
        user: UserRef.fromJson(((j['user'] as Map?) ?? const {}).cast<String, dynamic>()),
        cells: _i(j['cells']) ?? 0,
      );
}

/// The caller's own place on the weekly board (D10). [rank] is null when the caller holds no cells.
class LeaderboardMe {
  const LeaderboardMe({this.rank, this.cells = 0});
  final int? rank;
  final int cells;

  factory LeaderboardMe.fromJson(Map<String, dynamic> j) =>
      LeaderboardMe(rank: _i(j['rank']), cells: _i(j['cells']) ?? 0);

  @override
  bool operator ==(Object other) => other is LeaderboardMe && other.rank == rank && other.cells == cells;

  @override
  int get hashCode => Object.hash(rank, cells);
}

class Leaderboard {
  const Leaderboard({required this.week, required this.entries, this.me});
  final String week;
  final List<LeaderboardEntry> entries;

  /// Null when the server did not send it (older server).
  final LeaderboardMe? me;

  factory Leaderboard.fromJson(Map<String, dynamic> j) {
    final me = j['me'];
    return Leaderboard(
      week: (j['week'] ?? '').toString(),
      entries: ((j['entries'] as List?) ?? const [])
          .map((e) => LeaderboardEntry.fromJson((e as Map).cast<String, dynamic>()))
          .toList(),
      me: me is Map ? LeaderboardMe.fromJson(me.cast<String, dynamic>()) : null,
    );
  }
}

/// State of the decay freeze ("rest days") and how much of the quota is used (D10).
class FreezeStatus {
  const FreezeStatus({this.freezeUntil, this.usedDays, this.quotaDays, this.windowDays});

  /// Epoch ms; null when no freeze is running.
  final int? freezeUntil;

  /// Null when the server did not send the quota fields (older server).
  final int? usedDays;
  final int? quotaDays;
  final int? windowDays;

  bool get hasQuota => usedDays != null && quotaDays != null && quotaDays! > 0;

  factory FreezeStatus.fromJson(Map<String, dynamic> j) => FreezeStatus(
        freezeUntil: _i(j['freeze_until']),
        usedDays: _i(j['used_days']),
        quotaDays: _i(j['quota_days']),
        windowDays: _i(j['window_days']),
      );

  @override
  bool operator ==(Object other) =>
      other is FreezeStatus &&
      other.freezeUntil == freezeUntil &&
      other.usedDays == usedDays &&
      other.quotaDays == quotaDays &&
      other.windowDays == windowDays;

  @override
  int get hashCode => Object.hash(freezeUntil, usedDays, quotaDays, windowDays);
}

/// GET /me: the caller's own settings as the server has them.
class MeInfo {
  const MeInfo({required this.user, this.homeZones = const [], this.freeze = const FreezeStatus()});
  final UserRef user;
  final List<HomeZone> homeZones;
  final FreezeStatus freeze;

  factory MeInfo.fromJson(Map<String, dynamic> j) {
    final f = j['freeze'];
    return MeInfo(
      user: UserRef.fromJson(((j['user'] as Map?) ?? const {}).cast<String, dynamic>()),
      homeZones: ((j['home_zones'] as List?) ?? const [])
          .map((e) => HomeZone.fromJson((e as Map).cast<String, dynamic>()))
          .toList(),
      freeze: f is Map ? FreezeStatus.fromJson(f.cast<String, dynamic>()) : const FreezeStatus(),
    );
  }
}

class HomeZone {
  const HomeZone({required this.lat, required this.lng, required this.radiusM});
  final double lat;
  final double lng;
  final double radiusM;

  factory HomeZone.fromJson(Map<String, dynamic> j) => HomeZone(
        lat: _d(j['lat']) ?? 0,
        lng: _d(j['lng']) ?? 0,
        radiusM: _d(j['radius_m']) ?? 100,
      );

  Map<String, dynamic> toJson() => {'lat': lat, 'lng': lng, 'radius_m': radiusM};

  @override
  bool operator ==(Object other) =>
      other is HomeZone && other.lat == lat && other.lng == lng && other.radiusM == radiusM;

  @override
  int get hashCode => Object.hash(lat, lng, radiusM);
}

/// A signed-in session (the token is kept in memory and in secure storage).
class AuthSession {
  const AuthSession({required this.token, required this.user});
  final String token;
  final UserRef user;

  @override
  bool operator ==(Object other) =>
      other is AuthSession && other.token == token && other.user == user;

  @override
  int get hashCode => Object.hash(token, user);
}

/// A run as stored on this phone (the local database is the source of truth for runs).
/// state: recording | paused | finished. upload: none | queued | processing | done | failed.
class RunSummary {
  const RunSummary({
    required this.id,
    required this.startedAt,
    this.endedAt,
    this.state = 'recording',
    this.upload = 'none',
    this.attempts = 0,
    this.lastError,
    this.result,
  });

  final String id;
  final int startedAt;
  final int? endedAt;
  final String state;
  final String upload;
  final int attempts;
  final String? lastError;

  /// Last server answer, if any.
  final RunStatus? result;

  bool get uploadFailed => upload == 'failed';
  bool get uploadQueued => upload == 'queued';

  @override
  bool operator ==(Object other) =>
      other is RunSummary &&
      other.id == id &&
      other.startedAt == startedAt &&
      other.endedAt == endedAt &&
      other.state == state &&
      other.upload == upload &&
      other.attempts == attempts &&
      other.lastError == lastError &&
      other.result?.status == result?.status;

  @override
  int get hashCode =>
      Object.hash(id, startedAt, endedAt, state, upload, attempts, lastError, result?.status);
}

/// One `cell_changed` frame from the /live WebSocket.
class CellChange {
  const CellChange({
    required this.id,
    required this.lat,
    required this.lng,
    required this.owner,
    required this.mine,
    this.boundary = const [],
    this.strength,
  });

  final String id;
  final double lat;
  final double lng;

  /// Null when the cell has no visible owner: it is free, or its owner is hidden by privacy rules.
  final UserRef? owner;
  final bool mine;

  /// Hexagon corners (D10); empty when the server did not send them.
  final List<LatLngPoint> boundary;

  /// Only on frames about the receiver's own cell (D10).
  final double? strength;

  /// Returns null if the frame is not a well-formed cell_changed message.
  static CellChange? tryParse(Object? decoded) {
    if (decoded is! Map) return null;
    final j = decoded.cast<String, dynamic>();
    if (j['type'] != 'cell_changed') return null;
    final id = j['cell'];
    final lat = _d(j['lat']);
    final lng = _d(j['lng']);
    if (id is! String || lat == null || lng == null) return null;
    final o = j['owner'];
    final mine = j['mine'] == true;
    final s = _d(j['strength']);
    return CellChange(
      id: id,
      lat: lat,
      lng: lng,
      owner: o is Map ? UserRef.fromJson(o.cast<String, dynamic>()) : null,
      mine: mine,
      boundary: _boundary(j['boundary']),
      strength: mine && s != null ? s.clamp(0.0, 1.0).toDouble() : null,
    );
  }

  /// The server never sends a hidden cell's owner, so a change without owner is drawn as private
  /// until the next REST refresh shows whether the cell is free.
  Cell toCell() => Cell(
        id: id,
        lat: lat,
        lng: lng,
        boundary: boundary,
        owner: owner,
        mine: mine,
        hidden: owner == null && !mine,
        strength: strength,
      );
}
