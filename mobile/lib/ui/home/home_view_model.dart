import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/models.dart';
import '../../data/providers.dart';

/// View model of the home screen: the selected tab (state) and crash recovery.
class HomeViewModel extends Notifier<int> {
  static const int mapTab = 0;
  static const int runTab = 1;
  static const int profileTab = 2;

  @override
  int build() => runTab;

  void select(int index) => state = index;

  /// A run left unfinished by a previous process, or null.
  Future<RunSummary?> findUnfinishedRun() => ref.read(runRepositoryProvider).findUnfinishedRun();

  /// Finishes and queues it. False when it was too short and got deleted.
  Future<bool> finishRecovered(String runId) =>
      ref.read(runRepositoryProvider).finishRecoveredRun(runId);

  Future<void> discard(String runId) => ref.read(runRepositoryProvider).discardRun(runId);
}

final homeViewModelProvider = NotifierProvider<HomeViewModel, int>(HomeViewModel.new);

/// Keeps uploads of finished runs going while the home screen is open.
final uploadSyncProvider = Provider<void>((ref) {
  ref.watch(uploadTickerProvider);
});
