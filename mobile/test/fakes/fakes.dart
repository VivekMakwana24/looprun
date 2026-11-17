import 'dart:async';

import 'package:looprun/data/db/run_store.dart';
import 'package:looprun/data/models/api_exception.dart';
import 'package:looprun/data/models/models.dart';
import 'package:looprun/data/services/api_service.dart';
import 'package:looprun/data/services/foreground_service.dart';
import 'package:looprun/data/services/google_auth_service.dart';
import 'package:looprun/data/services/link_service.dart';
import 'package:looprun/data/services/live_service.dart';
import 'package:looprun/data/services/location_service.dart';
import 'package:looprun/data/services/permission_service.dart';
import 'package:looprun/data/upload/upload_queue.dart';
import 'package:looprun/domain/recorder/run_recorder.dart';

/// Lets everything that is already scheduled run: first the event queue (microtasks, zero-delay
/// timers, stream events), then a short real wait for the few things that use real timers
/// (review F24: the queue drain does not depend on how fast the CI machine is).
Future<void> settle([int ms = 15]) async {
  for (var i = 0; i < 20; i++) {
    await Future<void>.delayed(Duration.zero);
  }
  await Future<void>.delayed(Duration(milliseconds: ms));
}

class FakeLinkService implements LinkService {
  bool result = true;
  final List<String> opened = [];

  @override
  Future<bool> open(String url) async {
    opened.add(url);
    return result;
  }
}

class FakeApiService implements ApiService {
  Session session = const Session(accessToken: 'tok', user: UserRef(id: 'u1', name: 'dev'));
  ApiException? authError;
  final List<String> idTokens = [];

  List<Cell> cells = [];
  ApiException? cellsError;
  final List<String> bboxes = [];

  Leaderboard board = const Leaderboard(week: '2026-W45', entries: []);
  ApiException? boardError;
  int boardCalls = 0;

  final List<List<HomeZone>> zonePuts = [];
  ApiException? zoneError;

  /// What POST /me/freeze and GET /me report.
  FreezeStatus freezeStatus = const FreezeStatus(usedDays: 0, quotaDays: 30, windowDays: 90);
  ApiException? freezeError;
  final List<int> freezeCalls = [];

  /// The zones the server holds (GET /me returns them; PUT replaces them).
  List<HomeZone> serverZones = [];
  ApiException? meError;
  int meCalls = 0;

  bool deleted = false;
  final List<Map<String, String>> reports = [];
  ApiException? reportError;

  RunStatus runStatus = const RunStatus(id: 'x', status: RunStatus.accepted);
  final List<String> uploadedIds = [];

  @override
  Future<Session> authGoogle(String idToken) async {
    idTokens.add(idToken);
    final e = authError;
    if (e != null) throw e;
    return session;
  }

  @override
  Future<List<Cell>> getCells(String bbox) async {
    bboxes.add(bbox);
    final e = cellsError;
    if (e != null) throw e;
    return cells;
  }

  @override
  Future<Leaderboard> weeklyLeaderboard() async {
    boardCalls++;
    final e = boardError;
    if (e != null) throw e;
    return board;
  }

  @override
  Future<void> putHomeZones(List<HomeZone> zones) async {
    final e = zoneError;
    if (e != null) throw e;
    zonePuts.add(List<HomeZone>.of(zones));
    serverZones = List<HomeZone>.of(zones);
  }

  @override
  Future<FreezeStatus> setFreeze(int days) async {
    freezeCalls.add(days);
    final e = freezeError;
    if (e != null) throw e;
    return freezeStatus;
  }

  @override
  Future<MeInfo> getMe() async {
    meCalls++;
    final e = meError;
    if (e != null) throw e;
    return MeInfo(user: session.user, homeZones: List<HomeZone>.of(serverZones), freeze: freezeStatus);
  }

  @override
  Future<void> deleteAccount() async {
    deleted = true;
  }

  @override
  Future<void> report({required String kind, required String targetId, required String reason}) async {
    final e = reportError;
    if (e != null) throw e;
    reports.add({'kind': kind, 'target_id': targetId, 'reason': reason});
  }

  @override
  Future<RunStatus> uploadRun(RunUpload run) async {
    uploadedIds.add(run.id);
    return _status(run.id);
  }

  RunStatus _status(String id) => RunStatus(
        id: id,
        status: runStatus.status,
        distanceM: runStatus.distanceM,
        movingSeconds: runStatus.movingSeconds,
        loops: runStatus.loops,
        cellsClaimed: runStatus.cellsClaimed,
        cellsTakenFromOthers: runStatus.cellsTakenFromOthers,
        flags: runStatus.flags,
      );

  @override
  Future<RunStatus> getRun(String id) async => _status(id);
}

class FakeLocationService implements LocationService {
  bool enabled = true;
  GeoFix position = const GeoFix(lat: 50.0, lng: 8.7, t: 1, acc: 5);
  final StreamController<GeoFix> controller = StreamController<GeoFix>.broadcast();

  @override
  Future<bool> isEnabled() async => enabled;

  @override
  Stream<GeoFix> fixes() => controller.stream;

  @override
  Future<GeoFix> currentPosition() async => position;

  void emit(GeoFix fix) => controller.add(fix);
}

class FakePermissionService implements PermissionService {
  bool granted = true;
  bool notifications = true;
  int requests = 0;

  @override
  Future<bool> notificationsAllowed() async => notifications;

  @override
  Future<bool> hasLocation() async => granted;

  @override
  Future<bool> requestLocation() async {
    requests++;
    return granted;
  }
}

class FakeForegroundService implements ForegroundService {
  int starts = 0;
  int stops = 0;
  bool failStart = false;
  final List<String> texts = [];
  final StreamController<ForegroundAction> controller =
      StreamController<ForegroundAction>.broadcast();

  @override
  Future<void> start() async {
    if (failStart) throw StateError('no service');
    starts++;
  }

  @override
  Future<void> updateText(String text) async {
    texts.add(text);
  }

  @override
  Future<void> stop() async {
    stops++;
  }

  @override
  Future<void> stopIfRunning() async {}

  @override
  Stream<ForegroundAction> get actions => controller.stream;
}

class FakeGoogleAuthService implements GoogleAuthService {
  String? idToken = 'google-id-token';
  Object? error;
  int signOuts = 0;

  @override
  Future<String?> signInForIdToken() async {
    final e = error;
    if (e != null) throw e;
    return idToken;
  }

  @override
  Future<void> signOut() async {
    signOuts++;
  }
}

class FakeLiveService implements LiveService {
  final List<String> bboxes = [];
  final List<String> tokens = [];
  final List<StreamController<CellChange>> sockets = [];

  StreamController<CellChange> get latest => sockets.last;

  @override
  Stream<CellChange> connect({required String bbox, required String token}) {
    bboxes.add(bbox);
    tokens.add(token);
    final c = StreamController<CellChange>();
    sockets.add(c);
    return c.stream;
  }
}

/// One in-memory store used as both the run store and the upload store, like the Drift database.
class MemoryStore implements RunStore, UploadStore {
  /// The signed-in account; every read and write is scoped to it, like the Drift stores.
  String? userId = 'u1';

  final Map<String, _Run> _runs = {};
  final Map<String, UploadJob> jobs = {};

  /// Watchers are told about every write, like Drift's query streams.
  final StreamController<void> _changes = StreamController<void>.broadcast();
  void _changed() => _changes.add(null);

  /// The current value at once, then again after every write.
  Stream<T> _watch<T>(T Function() read) {
    late StreamController<T> c;
    StreamSubscription<void>? sub;
    c = StreamController<T>(
      onListen: () {
        c.add(read());
        sub = _changes.stream.listen((_) => c.add(read()));
      },
      onCancel: () => sub?.cancel(),
    );
    return c.stream;
  }
  bool failFixWrites = false;

  /// How many of the next markFinished calls throw (a full disk when the run is finished).
  int failMarkFinished = 0;

  /// While set, addFix waits for it before storing (a slow disk). Complete it to let the writes land.
  Completer<void>? holdFixWrites;

  /// Number of fixes of a run regardless of the signed-in account (for assertions).
  int storedFixCount(String runId) => _runs[runId]?.fixes.length ?? 0;

  /// Ids of the signed-in account's runs.
  Iterable<String> get runIds => _runs.values.where(_mine).map((r) => r.id);

  bool _mine(_Run r) => userId != null && r.owner == userId;

  _Run? _own(String id) {
    final r = _runs[id];
    return r != null && _mine(r) ? r : null;
  }

  String get _uid {
    final u = userId;
    if (u == null) throw StateError('Not signed in');
    return u;
  }

  RunSummary _summary(_Run r) => RunSummary(
        id: r.id,
        startedAt: r.startedAt,
        endedAt: r.endedAt,
        state: r.state,
        upload: jobs[r.id]?.stage.name ?? 'none',
        attempts: jobs[r.id]?.attempts ?? 0,
        lastError: jobs[r.id]?.lastError,
        result: jobs[r.id]?.result,
      );

  // RunStore
  @override
  Future<void> createRun(String id, int startedAt) async {
    _runs[id] = _Run(id, startedAt, _uid);
    _changed();
  }

  @override
  Future<void> addFix(String runId, GeoFix fix) async {
    if (failFixWrites) throw StateError('disk full');
    final hold = holdFixWrites;
    if (hold != null) await hold.future;
    final r = _own(runId);
    if (r == null) throw StateError('Run $runId not found');
    r.fixes.add(Fix(lat: fix.lat, lng: fix.lng, t: fix.t, acc: fix.acc, mock: fix.isMock));
  }

  @override
  Future<List<Fix>> fixesFor(String runId) async => List<Fix>.of(_own(runId)?.fixes ?? const []);

  @override
  Future<RunSummary?> runById(String id) async {
    final r = _own(id);
    return r == null ? null : _summary(r);
  }

  @override
  Future<RunSummary?> unfinishedRun() async {
    for (final r in _runs.values.where(_mine)) {
      if (r.state == 'recording' || r.state == 'paused') return _summary(r);
    }
    return null;
  }

  @override
  Future<void> setRunState(String id, String state) async {
    _own(id)?.state = state;
    _changed();
  }

  @override
  Future<void> markFinished(String id, int endedAt) async {
    if (failMarkFinished > 0) {
      failMarkFinished--;
      throw StateError('database or disk is full');
    }
    final r = _own(id)!;
    r.state = 'finished';
    r.endedAt = endedAt;
    jobs[id] = UploadJob(runId: id, stage: UploadStage.queued);
    _changed();
  }

  @override
  Future<void> discardRun(String id) async {
    if (_own(id) == null) return;
    _runs.remove(id);
    jobs.remove(id);
    _changed();
  }

  @override
  Stream<RunSummary?> watchRun(String id) => _watch(() => _own(id) == null ? null : _summary(_own(id)!));

  @override
  Stream<List<RunSummary>> watchRecentRuns({int limit = 10}) => _watch(
      () => _runs.values.where((r) => _mine(r) && r.state == 'finished').map(_summary).toList());

  @override
  Future<void> wipe() async {
    final uid = _uid;
    final gone = _runs.values.where((r) => r.owner == uid).map((r) => r.id).toList();
    for (final id in gone) {
      _runs.remove(id);
      jobs.remove(id);
    }
  }

  // UploadStore
  @override
  Future<List<UploadJob>> activeJobs() async => jobs.values
      .where((j) => _own(j.runId) != null)
      .where((j) => j.stage == UploadStage.queued || j.stage == UploadStage.processing)
      .toList();

  @override
  Future<UploadJob?> getJob(String runId) async => _own(runId) == null ? null : jobs[runId];

  @override
  Future<void> saveJob(UploadJob job) async {
    if (_own(job.runId) == null && _runs.containsKey(job.runId)) {
      throw StateError('Run ${job.runId} belongs to another account');
    }
    jobs[job.runId] = job;
    _changed();
  }

  @override
  Future<RunUpload> buildPayload(String runId) async {
    final r = _own(runId);
    if (r == null) throw StateError('Run $runId not found');
    return RunUpload(
      id: runId,
      startedAt: r.startedAt,
      endedAt: r.endedAt ?? r.startedAt,
      fixes: List<Fix>.of(r.fixes),
    );
  }
}

class _Run {
  _Run(this.id, this.startedAt, this.owner);
  final String id;
  final String owner;
  final int startedAt;
  int? endedAt;
  String state = 'recording';
  final List<Fix> fixes = [];
}
