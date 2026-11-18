import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/social_models.dart';
import '../../data/providers.dart';
import '../core/error_text.dart';
import '../core/paged_view_model.dart';

/// The feed: accepted runs of people the caller follows, plus the caller's own, newest first.
/// The server sends no route, start or end point; a card only has numbers.
class FeedViewModel extends PagedViewModel<RunCard> {
  final Set<String> _kudosBusy = {};

  @override
  Future<PagedResult<RunCard>> fetch(String? cursor) =>
      ref.read(feedRepositoryProvider).feed(cursor: cursor);

  @override
  String idOf(RunCard item) => item.id;

  RunCard? cardById(String id) {
    for (final c in state.items) {
      if (c.id == id) return c;
    }
    return null;
  }

  /// Gives or removes kudos on [card]. The heart changes at once and goes back if the server refuses.
  /// Returns a sentence for the user on failure, else null. Ignored while the same card is being sent.
  Future<String?> toggleKudos(RunCard card) async {
    if (!_kudosBusy.add(card.id)) return null;
    final give = !card.kudosByMe;
    replaceItem(card.copyWith(kudosByMe: give, kudosCount: math.max(0, card.kudosCount + (give ? 1 : -1))));
    try {
      final k = await ref.read(feedRepositoryProvider).setKudos(card.id, give);
      final now = cardById(card.id);
      if (now != null) replaceItem(now.copyWith(kudosByMe: k.kudosByMe, kudosCount: k.kudosCount));
      return null;
    } catch (e) {
      replaceItem(card);
      return errorText(e);
    } finally {
      _kudosBusy.remove(card.id);
    }
  }
}

final feedViewModelProvider =
    NotifierProvider.autoDispose<FeedViewModel, PagedState<RunCard>>(FeedViewModel.new);
