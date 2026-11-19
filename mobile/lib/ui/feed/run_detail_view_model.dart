import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/social_models.dart';
import '../../data/providers.dart';
import '../core/error_text.dart';
import 'feed_view_model.dart';

/// Which run the detail screen shows. Equal when the run id is equal; [card] only seeds the header.
class RunDetailArgs {
  const RunDetailArgs(this.runId, [this.card]);
  final String runId;
  final RunCard? card;

  @override
  bool operator ==(Object other) => other is RunDetailArgs && other.runId == runId;

  @override
  int get hashCode => runId.hashCode;
}

class RunDetailState {
  const RunDetailState({
    this.card,
    this.comments = const [],
    this.nextCursor,
    this.loading = false,
    this.loadingMore = false,
    this.posting = false,
    this.error,
    this.offline = false,
    this.loaded = false,
  });

  /// The run's numbers; null when the screen was opened from a notification and the card is not at hand.
  final RunCard? card;
  final List<Comment> comments;
  final String? nextCursor;
  final bool loading;
  final bool loadingMore;
  final bool posting;
  final String? error;
  final bool offline;
  final bool loaded;

  bool get hasMore => nextCursor != null && nextCursor!.isNotEmpty;

  RunDetailState copyWith({
    RunCard? card,
    List<Comment>? comments,
    String? nextCursor,
    bool clearCursor = false,
    bool? loading,
    bool? loadingMore,
    bool? posting,
    String? error,
    bool clearError = false,
    bool? offline,
    bool? loaded,
  }) {
    return RunDetailState(
      card: card ?? this.card,
      comments: comments ?? this.comments,
      nextCursor: clearCursor ? null : (nextCursor ?? this.nextCursor),
      loading: loading ?? this.loading,
      loadingMore: loadingMore ?? this.loadingMore,
      posting: posting ?? this.posting,
      error: clearError ? null : (error ?? this.error),
      offline: offline ?? this.offline,
      loaded: loaded ?? this.loaded,
    );
  }
}

/// One run with its comments: add, delete (own, or any when the run is yours), kudos.
class RunDetailViewModel extends AutoDisposeFamilyNotifier<RunDetailState, RunDetailArgs> {
  bool _alive = true;
  int _generation = 0;
  bool _kudosBusy = false;

  String get _runId => arg.runId;

  @override
  RunDetailState build(RunDetailArgs arg) {
    _alive = true;
    ref.onDispose(() => _alive = false);
    Future<void>.microtask(refresh);
    return RunDetailState(card: arg.card, loading: true);
  }

  Future<void> refresh() async {
    final gen = ++_generation;
    if (_alive) state = state.copyWith(loading: true, loadingMore: false, clearError: true);
    try {
      final page = await ref.read(feedRepositoryProvider).comments(_runId);
      if (!_alive || gen != _generation) return;
      state = RunDetailState(
        card: state.card,
        comments: page.items,
        nextCursor: page.nextCursor,
        loaded: true,
      );
    } catch (e) {
      if (!_alive || gen != _generation) return;
      state = state.copyWith(loading: false, error: errorText(e), offline: isOffline(e));
      return;
    }
    if (state.card == null) await _findCard(gen);
  }

  /// Opened from a notification: the numbers come from the caller's history (no error is shown when not found).
  Future<void> _findCard(int gen) async {
    try {
      final card = await ref.read(feedRepositoryProvider).ownCard(_runId);
      if (!_alive || gen != _generation || card == null) return;
      state = state.copyWith(card: card);
    } catch (_) {
      // The comments are the point of the screen; the header stays out.
    }
  }

  Future<void> loadMore() async {
    final s = state;
    if (s.loading || s.loadingMore || !s.hasMore) return;
    final gen = _generation;
    state = s.copyWith(loadingMore: true, clearError: true);
    try {
      final page = await ref.read(feedRepositoryProvider).comments(_runId, cursor: s.nextCursor);
      if (!_alive || gen != _generation) return;
      final seen = {for (final c in state.comments) c.id};
      state = state.copyWith(
        comments: [...state.comments, for (final c in page.items) if (!seen.contains(c.id)) c],
        nextCursor: page.nextCursor,
        clearCursor: page.nextCursor == null,
        loadingMore: false,
      );
    } catch (e) {
      if (!_alive || gen != _generation) return;
      state = state.copyWith(loadingMore: false, error: errorText(e), offline: isOffline(e));
    }
  }

  void _setCard(RunCard card) {
    if (!_alive) return;
    state = state.copyWith(card: card);
    // Keep the feed list in step when it is open.
    if (ref.exists(feedViewModelProvider)) {
      final feed = ref.read(feedViewModelProvider.notifier);
      if (feed.cardById(card.id) != null) feed.replaceItem(card);
    }
  }

  /// Sends a comment. Returns a sentence for the user on failure (the text stays in the box), else null.
  Future<String?> post(String text) async {
    if (state.posting) return null;
    state = state.copyWith(posting: true);
    try {
      final comment = await ref.read(feedRepositoryProvider).addComment(_runId, text);
      if (!_alive) return null;
      state = state.copyWith(comments: [...state.comments, comment], posting: false);
      final card = state.card;
      if (card != null) _setCard(card.copyWith(commentCount: card.commentCount + 1));
      return null;
    } catch (e) {
      if (_alive) state = state.copyWith(posting: false);
      return errorText(e);
    }
  }

  /// Deletes a comment (the server allows the author and the run's owner). Returns an error sentence or null.
  Future<String?> deleteComment(Comment comment) async {
    try {
      await ref.read(feedRepositoryProvider).deleteComment(_runId, comment.id);
      if (!_alive) return null;
      state = state.copyWith(comments: [for (final c in state.comments) if (c.id != comment.id) c]);
      final card = state.card;
      if (card != null) _setCard(card.copyWith(commentCount: math.max(0, card.commentCount - 1)));
      return null;
    } catch (e) {
      return errorText(e);
    }
  }

  /// Drops every comment of a user from the list (after blocking them).
  void removeCommentsOf(String userId) {
    if (!_alive) return;
    state = state.copyWith(comments: [for (final c in state.comments) if (c.user.id != userId) c]);
  }

  Future<String?> toggleKudos() async {
    final card = state.card;
    if (card == null || _kudosBusy) return null;
    _kudosBusy = true;
    final give = !card.kudosByMe;
    _setCard(card.copyWith(kudosByMe: give, kudosCount: math.max(0, card.kudosCount + (give ? 1 : -1))));
    try {
      final k = await ref.read(feedRepositoryProvider).setKudos(_runId, give);
      final now = state.card;
      if (now != null) _setCard(now.copyWith(kudosByMe: k.kudosByMe, kudosCount: k.kudosCount));
      return null;
    } catch (e) {
      _setCard(card);
      return errorText(e);
    } finally {
      _kudosBusy = false;
    }
  }
}

final runDetailViewModelProvider = NotifierProvider.autoDispose
    .family<RunDetailViewModel, RunDetailState, RunDetailArgs>(RunDetailViewModel.new);
