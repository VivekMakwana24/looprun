import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/social_models.dart';
import '../auth/auth_view_model.dart';
import 'error_text.dart';

/// State of a cursor list (feed, comments, followers...). [items] stay on screen while a reload runs or fails.
class PagedState<T> {
  const PagedState({
    this.items = const [],
    this.nextCursor,
    this.loading = false,
    this.loadingMore = false,
    this.error,
    this.offline = false,
    this.loaded = false,
  });

  final List<T> items;
  final String? nextCursor;

  /// The first page (or a refresh) is loading.
  final bool loading;
  final bool loadingMore;

  /// A sentence for the user, or null.
  final String? error;
  final bool offline;

  /// A first answer arrived at some point.
  final bool loaded;

  bool get hasMore => nextCursor != null && nextCursor!.isNotEmpty;

  /// Loaded fine and there is nothing to show.
  bool get isEmpty => loaded && items.isEmpty && error == null && !loading;

  PagedState<T> copyWith({
    List<T>? items,
    String? nextCursor,
    bool clearCursor = false,
    bool? loading,
    bool? loadingMore,
    String? error,
    bool clearError = false,
    bool? offline,
    bool? loaded,
  }) {
    return PagedState<T>(
      items: items ?? this.items,
      nextCursor: clearCursor ? null : (nextCursor ?? this.nextCursor),
      loading: loading ?? this.loading,
      loadingMore: loadingMore ?? this.loadingMore,
      error: clearError ? null : (error ?? this.error),
      offline: offline ?? this.offline,
      loaded: loaded ?? this.loaded,
    );
  }
}

/// Base of the list view models: first load when created, [refresh], [loadMore], and in-place edits.
/// Auto-disposed (leaving the screen drops the list) and per account (a new sign-in starts again).
abstract class PagedViewModel<T> extends AutoDisposeNotifier<PagedState<T>> {
  bool _alive = true;
  int _generation = 0;

  /// One page. [cursor] is null for the first page.
  Future<PagedResult<T>> fetch(String? cursor);

  /// Stable id of an item, to drop duplicates when pages overlap.
  String idOf(T item);

  @override
  PagedState<T> build() {
    _alive = true;
    ref.onDispose(() => _alive = false);
    ref.watch(authViewModelProvider.select((s) => s.user?.id));
    Future<void>.microtask(refresh);
    return PagedState<T>(loading: true);
  }

  /// Loads the first page again. Items already shown stay until the new page arrives.
  Future<void> refresh() async {
    final gen = ++_generation;
    if (_alive) state = state.copyWith(loading: true, loadingMore: false, clearError: true);
    try {
      final page = await fetch(null);
      if (!_alive || gen != _generation) return;
      state = PagedState<T>(items: page.items, nextCursor: page.nextCursor, loaded: true);
    } catch (e) {
      if (!_alive || gen != _generation) return;
      state = state.copyWith(loading: false, error: errorText(e), offline: isOffline(e));
    }
  }

  /// The next page, if there is one. A failure keeps what is shown and sets [PagedState.error].
  Future<void> loadMore() async {
    final s = state;
    if (s.loading || s.loadingMore || !s.hasMore) return;
    final gen = _generation;
    state = s.copyWith(loadingMore: true, clearError: true);
    try {
      final page = await fetch(s.nextCursor);
      if (!_alive || gen != _generation) return;
      final seen = {for (final i in state.items) idOf(i)};
      final fresh = [for (final i in page.items) if (!seen.contains(idOf(i))) i];
      state = state.copyWith(
        items: [...state.items, ...fresh],
        nextCursor: page.nextCursor,
        clearCursor: page.nextCursor == null,
        loadingMore: false,
      );
    } catch (e) {
      if (!_alive || gen != _generation) return;
      state = state.copyWith(loadingMore: false, error: errorText(e), offline: isOffline(e));
    }
  }

  /// "Try again" after a failure: reloads when nothing is shown, else asks for the next page again.
  Future<void> retry() => state.items.isEmpty || state.nextCursor == null ? refresh() : loadMore();

  /// Replaces the item with the same id.
  void replaceItem(T item) {
    if (!_alive) return;
    final id = idOf(item);
    state = state.copyWith(items: [for (final i in state.items) idOf(i) == id ? item : i]);
  }

  void removeItem(String id) {
    if (!_alive) return;
    state = state.copyWith(items: [for (final i in state.items) if (idOf(i) != id) i]);
  }

  bool get alive => _alive;
}
