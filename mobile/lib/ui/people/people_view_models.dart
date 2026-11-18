import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/social_models.dart';
import '../../data/providers.dart';
import '../core/error_text.dart';
import '../core/paged_view_model.dart';
import '../core/social_actions_view_model.dart';

/// Which people list a screen shows.
enum PeopleKind { followers, following, blocked, rivals }

/// Base of the lists of people. Rows can be followed and unfollowed in place.
abstract class PeopleViewModel extends PagedViewModel<UserListItem> {
  @override
  String idOf(UserListItem item) => item.id;

  /// Follows or unfollows [item] and updates the row. Returns a sentence on failure, else null.
  Future<String?> toggleFollow(UserListItem item) async {
    final out = await ref.read(socialActionsProvider.notifier).setFollowing(item.id, !item.isFollowing);
    if (!out.ok) return out.error;
    replaceItem(item.copyWith(isFollowing: out.value!.isFollowing));
    return null;
  }

  /// Unblocks [item] and removes the row. Returns a sentence on failure, else null.
  Future<String?> unblock(UserListItem item) async {
    final out = await ref.read(socialActionsProvider.notifier).unblock(item.id);
    if (!out.ok) return out.error;
    removeItem(item.id);
    return null;
  }
}

class FollowersViewModel extends PeopleViewModel {
  @override
  Future<PagedResult<UserListItem>> fetch(String? cursor) =>
      ref.read(userRepositoryProvider).followers(cursor: cursor);
}

class FollowingViewModel extends PeopleViewModel {
  @override
  Future<PagedResult<UserListItem>> fetch(String? cursor) =>
      ref.read(userRepositoryProvider).following(cursor: cursor);
}

/// People the caller blocked. Unblocking removes the row.
class BlockedViewModel extends PeopleViewModel {
  @override
  Future<PagedResult<UserListItem>> fetch(String? cursor) async {
    final page = await ref.read(userRepositoryProvider).blocks(cursor: cursor);
    return PagedResult(
      items: [for (final u in page.items) UserListItem(id: u.id, name: u.name)],
      nextCursor: page.nextCursor,
    );
  }
}

/// People the caller traded cells with in the last 30 days (at most 50, no paging).
class RivalsViewModel extends PeopleViewModel {
  @override
  Future<PagedResult<UserListItem>> fetch(String? cursor) async =>
      PagedResult(items: await ref.read(userRepositoryProvider).rivals());
}

final AutoDisposeNotifierProvider<PeopleViewModel, PagedState<UserListItem>> followersViewModelProvider =
    NotifierProvider.autoDispose<PeopleViewModel, PagedState<UserListItem>>(FollowersViewModel.new);
final AutoDisposeNotifierProvider<PeopleViewModel, PagedState<UserListItem>> followingViewModelProvider =
    NotifierProvider.autoDispose<PeopleViewModel, PagedState<UserListItem>>(FollowingViewModel.new);
final AutoDisposeNotifierProvider<PeopleViewModel, PagedState<UserListItem>> blockedViewModelProvider =
    NotifierProvider.autoDispose<PeopleViewModel, PagedState<UserListItem>>(BlockedViewModel.new);
final AutoDisposeNotifierProvider<PeopleViewModel, PagedState<UserListItem>> rivalsViewModelProvider =
    NotifierProvider.autoDispose<PeopleViewModel, PagedState<UserListItem>>(RivalsViewModel.new);

/// The provider behind a [PeopleKind].
AutoDisposeNotifierProvider<PeopleViewModel, PagedState<UserListItem>> peopleProviderFor(PeopleKind kind) {
  switch (kind) {
    case PeopleKind.followers:
      return followersViewModelProvider;
    case PeopleKind.following:
      return followingViewModelProvider;
    case PeopleKind.blocked:
      return blockedViewModelProvider;
    case PeopleKind.rivals:
      return rivalsViewModelProvider;
  }
}

// ---------------------------------------------------------------- search

class SearchState {
  const SearchState({
    this.query = '',
    this.results = const [],
    this.loading = false,
    this.error,
    this.offline = false,
    this.searched = false,
  });

  final String query;
  final List<UserListItem> results;
  final bool loading;
  final String? error;
  final bool offline;

  /// A search for [query] has finished (so "no results" is true).
  final bool searched;

  /// The prefix is long enough to ask the server (2..30).
  bool get queryTooShort => query.trim().runes.length < 2;
}

/// Prefix search of display names. Answers that arrive after a newer search started are dropped.
class UserSearchViewModel extends AutoDisposeNotifier<SearchState> {
  int _seq = 0;
  bool _alive = true;

  @override
  SearchState build() {
    _alive = true;
    ref.onDispose(() => _alive = false);
    return const SearchState();
  }

  Future<void> search(String raw) async {
    final q = raw.trim();
    final seq = ++_seq;
    if (q.runes.length < 2) {
      state = SearchState(query: q);
      return;
    }
    state = SearchState(query: q, results: state.results, loading: true);
    try {
      final found = await ref.read(userRepositoryProvider).search(q);
      if (!_alive || seq != _seq) return;
      state = SearchState(query: q, results: found, searched: true);
    } catch (e) {
      if (!_alive || seq != _seq) return;
      state = SearchState(query: q, error: errorText(e), offline: isOffline(e));
    }
  }

  Future<String?> toggleFollow(UserListItem item) async {
    final out = await ref.read(socialActionsProvider.notifier).setFollowing(item.id, !item.isFollowing);
    if (!out.ok) return out.error;
    if (!_alive) return null;
    state = SearchState(
      query: state.query,
      results: [for (final r in state.results) r.id == item.id ? r.copyWith(isFollowing: out.value!.isFollowing) : r],
      searched: state.searched,
    );
    return null;
  }
}

final userSearchViewModelProvider =
    NotifierProvider.autoDispose<UserSearchViewModel, SearchState>(UserSearchViewModel.new);
