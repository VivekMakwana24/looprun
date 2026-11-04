import '../../domain/recorder/run_recorder.dart';
import '../models/models.dart';

/// Local persistence of runs and their GPS fixes (Drift in the app, a map in tests).
/// Every fix is written here before anything else sees it.
abstract class RunStore {
  Future<void> createRun(String id, int startedAt);
  Future<void> addFix(String runId, GeoFix fix);

  /// All fixes of a run in time order.
  Future<List<Fix>> fixesFor(String runId);

  Future<RunSummary?> runById(String id);

  /// A run that was still recording or paused (the app died), newest first.
  Future<RunSummary?> unfinishedRun();

  Future<void> setRunState(String id, String state);

  /// Marks the run complete and queues it for upload.
  Future<void> markFinished(String id, int endedAt);

  Future<void> discardRun(String id);

  Stream<RunSummary?> watchRun(String id);
  Stream<List<RunSummary>> watchRecentRuns({int limit = 10});

  /// Deletes every run and fix (account deletion).
  Future<void> wipe();
}
