import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/api_exception.dart';
import '../../data/models/social_models.dart';
import '../../data/providers.dart';
import '../core/error_text.dart';
import '../core/social_actions_view_model.dart';

class PublicProfileState {
  const PublicProfileState({
    this.profile,
    this.loading = false,
    this.error,
    this.offline = false,
    this.notFound = false,
    this.busy = false,
  });

  final Profile? profile;
  final bool loading;
  final String? error;
  final bool offline;

  /// 404: unknown, being deleted, or blocked either way (the server does not say which).
  final bool notFound;

  /// A follow or block call is running.
  final bool busy;

  PublicProfileState copyWith({
    Profile? profile,
    bool? loading,
    String? error,
    bool clearError = false,
    bool? offline,
    bool? notFound,
    bool? busy,
  }) {
    return PublicProfileState(
      profile: profile ?? this.profile,
      loading: loading ?? this.loading,
      error: clearError ? null : (error ?? this.error),
      offline: offline ?? this.offline,
      notFound: notFound ?? this.notFound,
      busy: busy ?? this.busy,
    );
  }
}

/// A runner's public profile: stats, follow / unfollow, block. Never shows runs, times or places.
class PublicProfileViewModel extends AutoDisposeFamilyNotifier<PublicProfileState, String> {
  bool _alive = true;

  @override
  PublicProfileState build(String userId) {
    _alive = true;
    ref.onDispose(() => _alive = false);
    Future<void>.microtask(load);
    return const PublicProfileState(loading: true);
  }

  Future<void> load() async {
    if (_alive) state = state.copyWith(loading: true, clearError: true, notFound: false);
    try {
      final p = await ref.read(userRepositoryProvider).profile(arg);
      if (_alive) state = PublicProfileState(profile: p);
    } catch (e) {
      if (!_alive) return;
      state = state.copyWith(
        loading: false,
        error: errorText(e),
        offline: isOffline(e),
        notFound: e is ApiException && e.statusCode == 404,
      );
    }
  }

  /// Follows or unfollows. Returns a sentence on failure, else null.
  Future<String?> toggleFollow() async {
    final p = state.profile;
    if (p == null || p.isMe || state.busy) return null;
    state = state.copyWith(busy: true);
    final out = await ref.read(socialActionsProvider.notifier).setFollowing(p.id, !p.isFollowing);
    if (!_alive) return out.error;
    if (out.ok) {
      state = state.copyWith(profile: p.withFollow(out.value!), busy: false);
    } else {
      state = state.copyWith(busy: false);
    }
    return out.error;
  }

  /// Blocks this runner. After it the profile is gone for the caller (404), so the screen leaves.
  Future<String?> block() async {
    final p = state.profile;
    if (p == null || p.isMe || state.busy) return null;
    state = state.copyWith(busy: true);
    final out = await ref.read(socialActionsProvider.notifier).block(p.id);
    if (_alive) state = state.copyWith(busy: false);
    return out.error;
  }

  Future<String?> report(String reason) async {
    final p = state.profile;
    if (p == null) return null;
    final out = await ref.read(socialActionsProvider.notifier).report(ReportKind.user, p.id, reason);
    return out.error;
  }
}

final publicProfileViewModelProvider = NotifierProvider.autoDispose
    .family<PublicProfileViewModel, PublicProfileState, String>(PublicProfileViewModel.new);
