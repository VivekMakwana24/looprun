import '../../data/db/app_database.dart';

/// Finishes a run that was left unfinished (app killed or crashed) so it can be uploaded.
/// Returns true if the run was queued, false if it was too short and discarded.
Future<bool> finishRecoveredRun(AppDatabase db, RunRow run) async {
  final fixes = await db.fixesFor(run.id);
  if (fixes.length < 2) {
    await db.discardRun(run.id);
    return false;
  }
  await db.markFinished(run.id, fixes.last.t);
  return true;
}
