import 'package:looprun/data/models/api_exception.dart';
import 'package:looprun/data/models/models.dart';
import 'package:looprun/data/models/social_models.dart';
import 'package:looprun/data/services/social_api.dart';

/// The Phase 1a half of the fake API: every call is recorded in [socialCalls] and answers from the fields
/// below. [socialErrors] makes one call (by name, e.g. 'feed') throw; [socialError] makes all of them throw.
mixin FakeSocialApi implements SocialApi {
  final List<String> socialCalls = [];
  ApiException? socialError;
  final Map<String, ApiException> socialErrors = {};

  void _hit(String call) {
    socialCalls.add(call);
    final e = socialErrors[call] ?? socialError;
    if (e != null) throw e;
  }

  int count(String call) => socialCalls.where((c) => c == call || c.startsWith('$call:')).length;

  /// A page of a cursor list: the first page for a null cursor, page N for the cursor "pN".
  PagedResult<T> pageOf<T>(List<PagedResult<T>> pages, String? cursor) {
    if (pages.isEmpty) return PagedResult<T>(items: const []);
    final i = cursor == null ? 0 : int.parse(cursor.substring(1));
    return pages[i];
  }

  // ---- me / profile / people
  final List<String> renames = [];
  UserRef me = const UserRef(id: 'u1', name: 'dev');
  final Map<String, Profile> profiles = {};
  int followersCountAfterFollow = 1;
  List<PagedResult<UserListItem>> followerPages = [];
  List<PagedResult<UserListItem>> followingPages = [];
  List<UserListItem> people = [];
  List<UserListItem> rivalList = [];
  List<PagedResult<UserRef>> blockPages = [];
  final List<String> blocked = [];
  final List<String> unblocked = [];
  final List<String> searches = [];

  @override
  Future<UserRef> renameMe(String displayName) async {
    _hit('renameMe');
    renames.add(displayName);
    me = UserRef(id: me.id, name: displayName);
    return me;
  }

  @override
  Future<Profile> getProfile(String userId) async {
    _hit('getProfile:$userId');
    final p = profiles[userId];
    if (p == null) throw const ApiException(404, 'not found', code: 'not_found');
    return p;
  }

  @override
  Future<FollowState> follow(String userId) async {
    _hit('follow:$userId');
    return FollowState(isFollowing: true, followersCount: followersCountAfterFollow);
  }

  @override
  Future<FollowState> unfollow(String userId) async {
    _hit('unfollow:$userId');
    return const FollowState(isFollowing: false, followersCount: 0);
  }

  @override
  Future<PagedResult<UserListItem>> followers({String? cursor, int limit = 20}) async {
    _hit('followers');
    return pageOf(followerPages, cursor);
  }

  @override
  Future<PagedResult<UserListItem>> following({String? cursor, int limit = 20}) async {
    _hit('following');
    return pageOf(followingPages, cursor);
  }

  @override
  Future<List<UserListItem>> searchUsers(String query) async {
    _hit('searchUsers');
    searches.add(query);
    final q = query.toLowerCase();
    return [for (final p in people) if (p.name.toLowerCase().startsWith(q)) p];
  }

  @override
  Future<List<UserListItem>> rivals() async {
    _hit('rivals');
    return rivalList;
  }

  @override
  Future<void> blockUser(String userId) async {
    _hit('blockUser:$userId');
    blocked.add(userId);
  }

  @override
  Future<void> unblockUser(String userId) async {
    _hit('unblockUser:$userId');
    unblocked.add(userId);
  }

  @override
  Future<PagedResult<UserRef>> blocks({String? cursor, int limit = 20}) async {
    _hit('blocks');
    return pageOf(blockPages, cursor);
  }

  // ---- feed / history / kudos / comments
  List<PagedResult<RunCard>> feedPages = [];
  List<PagedResult<RunCard>> historyPages = [];
  final List<String?> historyStatuses = [];
  KudosState kudosAfterGive = const KudosState(kudosByMe: true, kudosCount: 1);
  KudosState kudosAfterRemove = const KudosState(kudosByMe: false, kudosCount: 0);
  List<PagedResult<Comment>> commentPages = [];
  final List<String> postedComments = [];
  final List<String> deletedComments = [];

  @override
  Future<PagedResult<RunCard>> feed({String? cursor, int limit = 20}) async {
    _hit('feed');
    return pageOf(feedPages, cursor);
  }

  @override
  Future<PagedResult<RunCard>> runHistory({String? cursor, int limit = 20, String? status}) async {
    _hit('runHistory');
    historyStatuses.add(status);
    return pageOf(historyPages, cursor);
  }

  @override
  Future<KudosState> giveKudos(String runId) async {
    _hit('giveKudos:$runId');
    return kudosAfterGive;
  }

  @override
  Future<KudosState> removeKudos(String runId) async {
    _hit('removeKudos:$runId');
    return kudosAfterRemove;
  }

  @override
  Future<PagedResult<Comment>> comments(String runId, {String? cursor, int limit = 20}) async {
    _hit('comments:$runId');
    return pageOf(commentPages, cursor);
  }

  @override
  Future<Comment> addComment(String runId, String text) async {
    _hit('addComment:$runId');
    postedComments.add(text);
    return Comment(
      id: 'new${postedComments.length}',
      runId: runId,
      user: me,
      text: text,
      createdAt: 1000,
      canDelete: true,
    );
  }

  @override
  Future<void> deleteComment(String runId, String commentId) async {
    _hit('deleteComment:$commentId');
    deletedComments.add(commentId);
  }

  // ---- battles
  BattleSummary summary = const BattleSummary();
  Rivalry rivalryResult = const Rivalry();
  List<LostCell> lostCells = [];

  @override
  Future<BattleSummary> battleSummary() async {
    _hit('battleSummary');
    return summary;
  }

  @override
  Future<Rivalry> rivalry({int days = 30}) async {
    _hit('rivalry');
    return rivalryResult;
  }

  @override
  Future<List<LostCell>> takeBack() async {
    _hit('takeBack');
    return lostCells;
  }

  // ---- notifications
  List<PagedResult<AppNotification>> notificationPages = [];
  int unread = 0;
  final List<List<String>> markedIds = [];
  int markedAll = 0;

  @override
  Future<NotificationPage> notifications({String? cursor, int limit = 20}) async {
    _hit('notifications');
    final p = pageOf(notificationPages, cursor);
    return NotificationPage(items: p.items, nextCursor: p.nextCursor, unreadCount: unread);
  }

  @override
  Future<int> unreadCount() async {
    _hit('unreadCount');
    return unread;
  }

  @override
  Future<void> markRead({List<String>? ids, bool all = false}) async {
    _hit(all ? 'markReadAll' : 'markRead');
    if (all) {
      markedAll++;
      unread = 0;
    } else {
      markedIds.add(List<String>.of(ids ?? const []));
    }
  }
}
