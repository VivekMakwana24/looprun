import '../models/social_models.dart';
import '../services/social_api.dart';

/// The in-app inbox (no push in Phase 1a).
class NotificationRepository {
  NotificationRepository({required SocialApi api}) : _api = api;
  final SocialApi _api;

  static const int maxIdsPerRequest = 100;

  Future<NotificationPage> page({String? cursor}) => _api.notifications(cursor: cursor);
  Future<int> unreadCount() => _api.unreadCount();

  /// Marks these read, 100 ids per request (the contract's limit). Nothing is sent for an empty list.
  Future<void> markRead(List<String> ids) async {
    for (var i = 0; i < ids.length; i += maxIdsPerRequest) {
      final end = i + maxIdsPerRequest < ids.length ? i + maxIdsPerRequest : ids.length;
      await _api.markRead(ids: ids.sublist(i, end));
    }
  }

  Future<void> markAllRead() => _api.markRead(all: true);
}
