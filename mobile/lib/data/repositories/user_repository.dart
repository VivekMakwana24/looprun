import '../../core/app_exception.dart';
import '../models/models.dart';
import '../models/social_models.dart';
import '../services/social_api.dart';
import 'text_rules.dart';

/// People: profiles, follows, search, rivals, blocks, and the caller's own display name.
class UserRepository {
  UserRepository({required SocialApi api}) : _api = api;
  final SocialApi _api;

  Future<Profile> profile(String userId) => _api.getProfile(userId);

  /// Follows ([follow] true) or unfollows. Both are idempotent on the server, so a retry is safe.
  Future<FollowState> setFollowing(String userId, bool follow) =>
      follow ? _api.follow(userId) : _api.unfollow(userId);

  Future<PagedResult<UserListItem>> followers({String? cursor}) => _api.followers(cursor: cursor);
  Future<PagedResult<UserListItem>> following({String? cursor}) => _api.following(cursor: cursor);
  Future<List<UserListItem>> rivals() => _api.rivals();

  /// Names starting with [query]. Under 2 characters nothing is asked (the server would answer 422);
  /// over 30 is cut. Returns an empty list then.
  Future<List<UserListItem>> search(String query) async {
    final q = query.trim();
    if (codePointLength(q) < minNameLength) return const [];
    final cut = codePointLength(q) > maxNameLength ? String.fromCharCodes(q.runes.take(maxNameLength)) : q;
    return _api.searchUsers(cut);
  }

  Future<void> block(String userId) => _api.blockUser(userId);
  Future<void> unblock(String userId) => _api.unblockUser(userId);
  Future<PagedResult<UserRef>> blocks({String? cursor}) => _api.blocks(cursor: cursor);

  /// The text a display name would be stored as, or an [AppException] saying what is wrong.
  static String checkDisplayName(String raw) {
    final name = normalizeName(raw);
    final n = codePointLength(name);
    if (n < minNameLength) throw const AppException('Use at least 2 characters.');
    if (n > maxNameLength) throw const AppException('Use at most 30 characters.');
    if (hasForbiddenCharacter(name)) throw const AppException('Use letters, numbers and normal punctuation only.');
    return name;
  }

  /// PATCH /me. Returns the caller as the server stored it.
  Future<UserRef> rename(String raw) => _api.renameMe(checkDisplayName(raw));
}
