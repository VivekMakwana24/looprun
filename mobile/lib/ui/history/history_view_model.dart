import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/social_models.dart';
import '../../data/providers.dart';
import '../core/paged_view_model.dart';

/// The caller's own run history (GET /runs), newest first, every status.
class HistoryViewModel extends PagedViewModel<RunCard> {
  @override
  Future<PagedResult<RunCard>> fetch(String? cursor) =>
      ref.read(feedRepositoryProvider).history(cursor: cursor);

  @override
  String idOf(RunCard item) => item.id;
}

final historyViewModelProvider =
    NotifierProvider.autoDispose<HistoryViewModel, PagedState<RunCard>>(HistoryViewModel.new);
