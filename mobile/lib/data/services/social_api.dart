import '../models/models.dart';
import '../models/social_models.dart';

/// The Phase 1a calls of docs/CONTRACT.openapi.yaml: profiles, follows, feed, kudos, comments, battles,
/// notifications, blocks. [ApiService] extends this; tests use a fake of it.
abstract class SocialApi {
  /// PATCH /me. Returns the caller as the server now has it.
  Future<UserRef> renameMe(String displayName);

  Future<Profile> getProfile(String userId);
  Future<FollowState> follow(String userId);
  Future<FollowState> unfollow(String userId);
  Future<PagedResult<UserListItem>> followers({String? cursor, int limit = 20});
  Future<PagedResult<UserListItem>> following({String? cursor, int limit = 20});

  /// Prefix search, 2..30 characters (the server answers 422 otherwise).
  Future<List<UserListItem>> searchUsers(String query);
  Future<List<UserListItem>> rivals();

  Future<PagedResult<RunCard>> feed({String? cursor, int limit = 20});

  /// GET /runs: the caller's own runs. [status] is one of the RunStatus values.
  Future<PagedResult<RunCard>> runHistory({String? cursor, int limit = 20, String? status});

  Future<KudosState> giveKudos(String runId);
  Future<KudosState> removeKudos(String runId);
  Future<PagedResult<Comment>> comments(String runId, {String? cursor, int limit = 20});
  Future<Comment> addComment(String runId, String text);
  Future<void> deleteComment(String runId, String commentId);

  Future<BattleSummary> battleSummary();
  Future<Rivalry> rivalry({int days = 30});
  Future<List<LostCell>> takeBack();

  Future<NotificationPage> notifications({String? cursor, int limit = 20});
  Future<int> unreadCount();

  /// Exactly one of [ids] (at most 100) or [all].
  Future<void> markRead({List<String>? ids, bool all = false});

  Future<void> blockUser(String userId);
  Future<void> unblockUser(String userId);
  Future<PagedResult<UserRef>> blocks({String? cursor, int limit = 20});
}
