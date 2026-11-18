// Plain immutable models for the Phase 1a endpoints of docs/CONTRACT.openapi.yaml (social + battles).
// No Flutter imports. Missing optional fields get neutral defaults; the server never sends route lines here.

import 'models.dart';

double? _d(Object? v) => v is num ? v.toDouble() : null;
int? _i(Object? v) => v is num ? v.toInt() : null;
String? _s(Object? v) => v is String ? v : null;
Map<String, dynamic> _m(Object? v) => v is Map ? v.cast<String, dynamic>() : const <String, dynamic>{};
List<Map<String, dynamic>> _maps(Object? v) =>
    v is List ? <Map<String, dynamic>>[for (final e in v) if (e is Map) e.cast<String, dynamic>()] : const [];
UserRef _user(Object? v) => UserRef.fromJson(_m(v));
UserRef? _userOrNull(Object? v) => v is Map ? UserRef.fromJson(v.cast<String, dynamic>()) : null;

/// One page of a cursor list. [nextCursor] is null at the end.
class PagedResult<T> {
  const PagedResult({required this.items, this.nextCursor});
  final List<T> items;
  final String? nextCursor;

  bool get hasMore => nextCursor != null && nextCursor!.isNotEmpty;

  factory PagedResult.fromJson(Map<String, dynamic> j, T Function(Map<String, dynamic>) item) =>
      PagedResult(items: _maps(j['items']).map(item).toList(), nextCursor: _s(j['next_cursor']));
}

class UserListItem {
  const UserListItem({required this.id, required this.name, this.isFollowing = false, this.followsMe = false});
  final String id;
  final String name;
  final bool isFollowing;
  final bool followsMe;

  factory UserListItem.fromJson(Map<String, dynamic> j) => UserListItem(
        id: (j['id'] ?? '').toString(),
        name: (j['name'] ?? '').toString(),
        isFollowing: j['is_following'] == true,
        followsMe: j['follows_me'] == true,
      );

  UserListItem copyWith({bool? isFollowing}) =>
      UserListItem(id: id, name: name, isFollowing: isFollowing ?? this.isFollowing, followsMe: followsMe);

  @override
  bool operator ==(Object other) =>
      other is UserListItem &&
      other.id == id &&
      other.name == name &&
      other.isFollowing == isFollowing &&
      other.followsMe == followsMe;

  @override
  int get hashCode => Object.hash(id, name, isFollowing, followsMe);
}

class Profile {
  const Profile({
    required this.id,
    required this.name,
    this.cellsHeld = 0,
    this.weeklyRank,
    this.followersCount = 0,
    this.followingCount = 0,
    this.joinedAt,
    this.isMe = false,
    this.isFollowing = false,
    this.followsMe = false,
  });
  final String id;
  final String name;
  final int cellsHeld;
  final int? weeklyRank;
  final int followersCount;
  final int followingCount;

  /// Epoch ms.
  final int? joinedAt;
  final bool isMe;
  final bool isFollowing;
  final bool followsMe;

  factory Profile.fromJson(Map<String, dynamic> j) => Profile(
        id: (j['id'] ?? '').toString(),
        name: (j['name'] ?? '').toString(),
        cellsHeld: _i(j['cells_held']) ?? 0,
        weeklyRank: _i(j['weekly_rank']),
        followersCount: _i(j['followers_count']) ?? 0,
        followingCount: _i(j['following_count']) ?? 0,
        joinedAt: _i(j['joined_at']),
        isMe: j['is_me'] == true,
        isFollowing: j['is_following'] == true,
        followsMe: j['follows_me'] == true,
      );

  Profile withFollow(FollowState f) => Profile(
        id: id,
        name: name,
        cellsHeld: cellsHeld,
        weeklyRank: weeklyRank,
        followersCount: f.followersCount,
        followingCount: followingCount,
        joinedAt: joinedAt,
        isMe: isMe,
        isFollowing: f.isFollowing,
        followsMe: followsMe,
      );
}

class FollowState {
  const FollowState({required this.isFollowing, required this.followersCount});
  final bool isFollowing;
  final int followersCount;

  factory FollowState.fromJson(Map<String, dynamic> j) =>
      FollowState(isFollowing: j['is_following'] == true, followersCount: _i(j['followers_count']) ?? 0);

  @override
  bool operator ==(Object other) =>
      other is FollowState && other.isFollowing == isFollowing && other.followersCount == followersCount;

  @override
  int get hashCode => Object.hash(isFollowing, followersCount);
}

class KudosState {
  const KudosState({required this.kudosByMe, required this.kudosCount});
  final bool kudosByMe;
  final int kudosCount;

  factory KudosState.fromJson(Map<String, dynamic> j) =>
      KudosState(kudosByMe: j['kudos_by_me'] == true, kudosCount: _i(j['kudos_count']) ?? 0);

  @override
  bool operator ==(Object other) =>
      other is KudosState && other.kudosByMe == kudosByMe && other.kudosCount == kudosCount;

  @override
  int get hashCode => Object.hash(kudosByMe, kudosCount);
}

class TakenFrom {
  const TakenFrom({required this.user, required this.cells});
  final UserRef user;
  final int cells;

  factory TakenFrom.fromJson(Map<String, dynamic> j) =>
      TakenFrom(user: _user(j['user']), cells: _i(j['cells']) ?? 0);
}

/// A run as shown in the feed and in the run history. Never carries a route, loop shape or start/end point.
class RunCard {
  const RunCard({
    required this.id,
    required this.user,
    required this.startedAt,
    this.distanceM,
    this.movingSeconds,
    this.paceSecPerKm,
    this.cellsClaimed = 0,
    this.cellsTaken = 0,
    this.takenFrom = const [],
    this.takenFromHidden = 0,
    this.loopCount = 0,
    this.kudosCount = 0,
    this.kudosByMe = false,
    this.commentCount = 0,
    this.status = RunStatus.accepted,
  });

  final String id;
  final UserRef user;

  /// Epoch ms.
  final int startedAt;

  /// Null while the run is still processing.
  final double? distanceM;
  final int? movingSeconds;

  /// Seconds per kilometre; null under 100 m or while processing.
  final double? paceSecPerKm;
  final int cellsClaimed;
  final int cellsTaken;
  final List<TakenFrom> takenFrom;
  final int takenFromHidden;
  final int loopCount;
  final int kudosCount;
  final bool kudosByMe;
  final int commentCount;
  final String status;

  bool get isAccepted => status == RunStatus.accepted;
  bool get isProcessing => status == RunStatus.processing;

  factory RunCard.fromJson(Map<String, dynamic> j) => RunCard(
        id: (j['id'] ?? '').toString(),
        user: _user(j['user']),
        startedAt: _i(j['started_at']) ?? 0,
        distanceM: _d(j['distance_m']),
        movingSeconds: _i(j['moving_seconds']),
        paceSecPerKm: _d(j['pace_s_per_km']),
        cellsClaimed: _i(j['cells_claimed']) ?? 0,
        cellsTaken: _i(j['cells_taken']) ?? 0,
        takenFrom: _maps(j['taken_from']).map(TakenFrom.fromJson).toList(),
        takenFromHidden: _i(j['taken_from_hidden']) ?? 0,
        loopCount: _i(j['loop_count']) ?? 0,
        kudosCount: _i(j['kudos_count']) ?? 0,
        kudosByMe: j['kudos_by_me'] == true,
        commentCount: _i(j['comment_count']) ?? 0,
        status: (j['status'] ?? RunStatus.accepted).toString(),
      );

  RunCard copyWith({int? kudosCount, bool? kudosByMe, int? commentCount}) => RunCard(
        id: id,
        user: user,
        startedAt: startedAt,
        distanceM: distanceM,
        movingSeconds: movingSeconds,
        paceSecPerKm: paceSecPerKm,
        cellsClaimed: cellsClaimed,
        cellsTaken: cellsTaken,
        takenFrom: takenFrom,
        takenFromHidden: takenFromHidden,
        loopCount: loopCount,
        kudosCount: kudosCount ?? this.kudosCount,
        kudosByMe: kudosByMe ?? this.kudosByMe,
        commentCount: commentCount ?? this.commentCount,
        status: status,
      );
}

class Comment {
  const Comment({
    required this.id,
    required this.runId,
    required this.user,
    required this.text,
    required this.createdAt,
    this.hidden = false,
    this.canDelete = false,
  });
  final String id;
  final String runId;
  final UserRef user;
  final String text;

  /// Epoch ms.
  final int createdAt;

  /// True only for the author, whose comment moderation hid.
  final bool hidden;
  final bool canDelete;

  factory Comment.fromJson(Map<String, dynamic> j) => Comment(
        id: (j['id'] ?? '').toString(),
        runId: (j['run_id'] ?? '').toString(),
        user: _user(j['user']),
        text: (j['text'] ?? '').toString(),
        createdAt: _i(j['created_at']) ?? 0,
        hidden: j['hidden'] == true,
        canDelete: j['can_delete'] == true,
      );
}

class BattleCounts {
  const BattleCounts({this.taken = 0, this.lost = 0});
  final int taken;
  final int lost;

  factory BattleCounts.fromJson(Map<String, dynamic> j) =>
      BattleCounts(taken: _i(j['taken']) ?? 0, lost: _i(j['lost']) ?? 0);
}

class BattleSummary {
  const BattleSummary({this.days = 7, this.taken = 0, this.lost = 0, this.net = 0, this.battles = 0});
  final int days;
  final int taken;
  final int lost;
  final int net;
  final int battles;

  factory BattleSummary.fromJson(Map<String, dynamic> j) => BattleSummary(
        days: _i(j['days']) ?? 7,
        taken: _i(j['taken']) ?? 0,
        lost: _i(j['lost']) ?? 0,
        net: _i(j['net']) ?? ((_i(j['taken']) ?? 0) - (_i(j['lost']) ?? 0)),
        battles: _i(j['battles']) ?? 0,
      );
}

class Rival {
  const Rival({
    required this.user,
    this.taken = 0,
    this.lost = 0,
    this.net = 0,
    this.lastBattleAt,
    this.isFollowing = false,
  });
  final UserRef user;

  /// Cells the caller took from them.
  final int taken;

  /// Cells they took from the caller.
  final int lost;
  final int net;
  final int? lastBattleAt;
  final bool isFollowing;

  factory Rival.fromJson(Map<String, dynamic> j) => Rival(
        user: _user(j['user']),
        taken: _i(j['taken']) ?? 0,
        lost: _i(j['lost']) ?? 0,
        net: _i(j['net']) ?? 0,
        lastBattleAt: _i(j['last_battle_at']),
        isFollowing: j['is_following'] == true,
      );
}

class Rivalry {
  const Rivalry({this.days = 30, this.rivals = const [], this.unattributed = const BattleCounts()});
  final int days;
  final List<Rival> rivals;
  final BattleCounts unattributed;

  factory Rivalry.fromJson(Map<String, dynamic> j) => Rivalry(
        days: _i(j['days']) ?? 30,
        rivals: _maps(j['rivals']).map(Rival.fromJson).toList(),
        unattributed: BattleCounts.fromJson(_m(j['unattributed'])),
      );
}

/// A cell the caller lost in the last 7 days and does not hold now ("take it back").
class LostCell {
  const LostCell({
    required this.cell,
    this.lat,
    this.lng,
    this.boundary = const [],
    this.lostAt,
    this.lostTo,
  });
  final String cell;
  final double? lat;
  final double? lng;

  /// Hexagon corners (D10); empty when missing.
  final List<LatLngPoint> boundary;

  /// Epoch ms.
  final int? lostAt;

  /// Null when the taker's name is hidden or the taker is gone.
  final UserRef? lostTo;

  factory LostCell.fromJson(Map<String, dynamic> j) => LostCell(
        cell: (j['cell'] ?? '').toString(),
        lat: _d(j['lat']),
        lng: _d(j['lng']),
        boundary: parseBoundary(j['boundary']),
        lostAt: _i(j['lost_at']),
        lostTo: _userOrNull(j['lost_to']),
      );
}

class NotificationType {
  const NotificationType._();
  static const cellsTaken = 'cells_taken';
  static const newFollower = 'new_follower';
  static const kudos = 'kudos';
  static const comment = 'comment';
}

/// One inbox entry. (Not called Notification: that is a Flutter class.)
class AppNotification {
  const AppNotification({
    required this.id,
    required this.type,
    required this.createdAt,
    this.read = false,
    this.actor,
    this.cells,
    this.cellsUnattributed,
    this.runId,
    this.commentId,
    this.commentPreview,
  });
  final String id;
  final String type;

  /// Epoch ms: when it became visible.
  final int createdAt;
  final bool read;
  final UserRef? actor;
  final int? cells;
  final int? cellsUnattributed;
  final String? runId;
  final String? commentId;
  final String? commentPreview;

  factory AppNotification.fromJson(Map<String, dynamic> j) => AppNotification(
        id: (j['id'] ?? '').toString(),
        type: (j['type'] ?? '').toString(),
        createdAt: _i(j['created_at']) ?? 0,
        read: j['read'] == true,
        actor: _userOrNull(j['actor']),
        cells: _i(j['cells']),
        cellsUnattributed: _i(j['cells_unattributed']),
        runId: _s(j['run_id']),
        commentId: _s(j['comment_id']),
        commentPreview: _s(j['comment_preview']),
      );

  AppNotification asRead() => AppNotification(
        id: id,
        type: type,
        createdAt: createdAt,
        read: true,
        actor: actor,
        cells: cells,
        cellsUnattributed: cellsUnattributed,
        runId: runId,
        commentId: commentId,
        commentPreview: commentPreview,
      );
}

class NotificationPage {
  const NotificationPage({required this.items, this.nextCursor, this.unreadCount = 0});
  final List<AppNotification> items;
  final String? nextCursor;
  final int unreadCount;

  factory NotificationPage.fromJson(Map<String, dynamic> j) => NotificationPage(
        items: _maps(j['items']).map(AppNotification.fromJson).toList(),
        nextCursor: _s(j['next_cursor']),
        unreadCount: _i(j['unread_count']) ?? 0,
      );
}
