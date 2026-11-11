import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/api_exception.dart';
import '../../data/models/models.dart';
import '../../data/providers.dart';
import '../auth/auth_view_model.dart';

/// The stored run (updates as the upload progresses).
final runResultProvider = StreamProvider.autoDispose.family<RunSummary?, String>((ref, id) {
  ref.watch(authViewModelProvider.select((s) => s.user?.id));
  return ref.watch(runRepositoryProvider).watchRun(id);
});

/// Commands of the result screen.
class RunResultViewModel {
  RunResultViewModel(this._ref);
  final Ref _ref;

  Future<void> retryUpload(String runId) => _ref.read(runRepositoryProvider).retryUpload(runId);

  /// Returns the message to show the user.
  Future<String> report(String runId, String reason) async {
    try {
      await _ref.read(runRepositoryProvider).reportRun(runId, reason);
      return 'Report sent. Thank you.';
    } on ApiException catch (e) {
      return e.statusCode == 429
          ? 'You have sent too many reports. Try again later.'
          : 'Could not send the report: ${e.message}';
    } catch (e) {
      return 'Could not send the report: $e';
    }
  }
}

final runResultViewModelProvider = Provider<RunResultViewModel>((ref) => RunResultViewModel(ref));
