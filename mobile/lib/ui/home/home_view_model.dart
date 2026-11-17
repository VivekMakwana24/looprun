import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/models.dart';
import '../../data/providers.dart';

/// View model of the home frame: crash recovery. (The selected lane is the route.)
class HomeViewModel extends Notifier<void> {
  @override
  void build() {}

  /// A run left unfinished by a previous process, or null.
  Future<RunSummary?> findUnfinishedRun() => ref.read(runRepositoryProvider).findUnfinishedRun();

  /// Finishes and queues it. False when it was too short and got deleted.
  Future<bool> finishRecovered(String runId) =>
      ref.read(runRepositoryProvider).finishRecoveredRun(runId);

  Future<void> discard(String runId) => ref.read(runRepositoryProvider).discardRun(runId);
}

final homeViewModelProvider = NotifierProvider<HomeViewModel, void>(HomeViewModel.new);

/// Keeps uploads of finished runs going while the app's main frame is open.
final uploadSyncProvider = Provider<void>((ref) {
  ref.watch(uploadTickerProvider);
});
