import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/models.dart';
import '../../data/models/recording_snapshot.dart';
import '../../data/providers.dart';
import '../../domain/recorder/loop_gap.dart';
import '../auth/auth_view_model.dart';

/// View model of the Run tab. The state is the repository's [RecordingSnapshot]; commands go back to it.
class RunViewModel extends Notifier<RecordingSnapshot> {
  @override
  RecordingSnapshot build() {
    final repo = ref.watch(runRepositoryProvider);
    final sub = repo.snapshots.listen((s) => state = s);
    ref.onDispose(sub.cancel);
    return repo.current;
  }

  /// Called only when the user taps Start.
  Future<void> start() => ref.read(runRepositoryProvider).start();
  Future<void> pause() => ref.read(runRepositoryProvider).pause();
  Future<void> resume() => ref.read(runRepositoryProvider).resume();
  Future<void> stop() => ref.read(runRepositoryProvider).stop();

  /// The result screen was opened for the finished run.
  void acknowledge() => ref.read(runRepositoryProvider).acknowledge();
}

final runViewModelProvider = NotifierProvider<RunViewModel, RecordingSnapshot>(RunViewModel.new);

/// The last finished runs on this phone, newest first.
final recentRunsProvider = StreamProvider.autoDispose<List<RunSummary>>((ref) {
  // Start over when another account signs in: the list is per account.
  ref.watch(authViewModelProvider.select((s) => s.user?.id));
  return ref.watch(runRepositoryProvider).watchRecentRuns(limit: 10);
});

/// The path so far, thinned for drawing, with the distance left to close a loop (a hint only: the server
/// decides which loops count). Recomputed when a new point arrives.
final loopSketchProvider = Provider.autoDispose<LoopSketch>((ref) {
  final path = ref.watch(runViewModelProvider.select((s) => s.path));
  return buildLoopSketch(path);
});

/// Uploads of finished runs that have not reached the server yet.
class UploadSummary {
  const UploadSummary({this.waiting = 0, this.failed = 0, this.retrying = false, this.runId});

  /// Runs saved on this phone and still to be sent.
  final int waiting;

  /// Runs whose upload was given up; they need "Try again".
  final int failed;

  /// At least one waiting run has already failed to send (usually: no connection).
  final bool retrying;

  /// The newest run that is waiting or failed, to open from the notice.
  final String? runId;

  bool get isEmpty => waiting == 0 && failed == 0;
}

final uploadSummaryProvider = Provider.autoDispose<UploadSummary>((ref) {
  final runs = ref.watch(recentRunsProvider).valueOrNull ?? const <RunSummary>[];
  var waiting = 0;
  var failed = 0;
  var retrying = false;
  String? runId;
  for (final r in runs) {
    if (r.uploadFailed) {
      failed++;
      runId ??= r.id;
    } else if (r.uploadQueued) {
      waiting++;
      if (r.attempts > 0) retrying = true;
      runId ??= r.id;
    }
  }
  return UploadSummary(waiting: waiting, failed: failed, retrying: retrying, runId: runId);
});
