import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/models.dart';
import '../../data/models/recording_snapshot.dart';
import '../../data/providers.dart';
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
