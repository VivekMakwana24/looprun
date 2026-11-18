import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/social_models.dart';
import '../../data/providers.dart';
import '../auth/auth_view_model.dart';
import '../core/paged_view_model.dart';

/// Unread notifications for the bell on the map. Null while unknown (no badge). There is no push in
/// Phase 1a, so it is read when the map opens, when the caller comes back to the map lane, after the board
/// reloads, and whenever the inbox changes.
class UnreadCountViewModel extends AutoDisposeNotifier<int?> {
  bool _alive = true;

  @override
  int? build() {
    _alive = true;
    ref.onDispose(() => _alive = false);
    ref.watch(authViewModelProvider.select((s) => s.user?.id));
    Future<void>.microtask(refresh);
    return null;
  }

  Future<void> refresh() async {
    try {
      final n = await ref.read(notificationRepositoryProvider).unreadCount();
      if (_alive) state = n;
    } catch (_) {
      // Keep the number that was shown; the bell must not turn into an error.
    }
  }

  void set(int? count) {
    if (_alive) state = count;
  }
}

final unreadCountProvider =
    NotifierProvider.autoDispose<UnreadCountViewModel, int?>(UnreadCountViewModel.new);

/// The notifications inbox, newest first. Opening an entry marks it read.
class InboxViewModel extends PagedViewModel<AppNotification> {
  @override
  Future<PagedResult<AppNotification>> fetch(String? cursor) async {
    final page = await ref.read(notificationRepositoryProvider).page(cursor: cursor);
    ref.read(unreadCountProvider.notifier).set(page.unreadCount);
    return PagedResult(items: page.items, nextCursor: page.nextCursor);
  }

  @override
  String idOf(AppNotification item) => item.id;

  /// Marks one entry read (the number on the bell drops by one). A failure leaves it unread; nothing is said.
  Future<void> markRead(AppNotification item) async {
    if (item.read) return;
    final before = ref.read(unreadCountProvider);
    replaceItem(item.asRead());
    if (before != null && before > 0) ref.read(unreadCountProvider.notifier).set(before - 1);
    try {
      await ref.read(notificationRepositoryProvider).markRead([item.id]);
    } catch (_) {
      replaceItem(item);
      await ref.read(unreadCountProvider.notifier).refresh();
    }
  }

  /// Marks everything read. Returns false when it did not work.
  Future<bool> markAllRead() async {
    try {
      await ref.read(notificationRepositoryProvider).markAllRead();
    } catch (_) {
      return false;
    }
    if (!alive) return true;
    state = state.copyWith(items: [for (final i in state.items) i.asRead()]);
    ref.read(unreadCountProvider.notifier).set(0);
    return true;
  }
}

final inboxViewModelProvider =
    NotifierProvider.autoDispose<InboxViewModel, PagedState<AppNotification>>(InboxViewModel.new);
