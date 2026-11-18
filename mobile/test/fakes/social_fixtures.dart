import 'package:looprun/data/models/models.dart';
import 'package:looprun/data/models/social_models.dart';

UserRef user(String id, [String? name]) => UserRef(id: id, name: name ?? 'User $id');

RunCard card(
  String id, {
  String owner = 'u2',
  String ownerName = 'Bob',
  int startedAt = 1700000000000,
  double? distanceM = 5200,
  int? movingSeconds = 1650,
  double? pace = 317,
  int claimed = 14,
  int taken = 0,
  List<TakenFrom> takenFrom = const [],
  int takenHidden = 0,
  int kudos = 0,
  bool kudosByMe = false,
  int comments = 0,
  String status = 'accepted',
}) =>
    RunCard(
      id: id,
      user: UserRef(id: owner, name: ownerName),
      startedAt: startedAt,
      distanceM: distanceM,
      movingSeconds: movingSeconds,
      paceSecPerKm: pace,
      cellsClaimed: claimed,
      cellsTaken: taken,
      takenFrom: takenFrom,
      takenFromHidden: takenHidden,
      loopCount: 1,
      kudosCount: kudos,
      kudosByMe: kudosByMe,
      commentCount: comments,
      status: status,
    );

Map<String, dynamic> cardJson(String id) => {
      'id': id,
      'user': {'id': 'u2', 'name': 'Bob'},
      'started_at': 1700000000000,
      'distance_m': 5200.0,
      'moving_seconds': 1650,
      'pace_s_per_km': 317.3,
      'cells_claimed': 14,
      'cells_taken': 5,
      'taken_from': [
        {
          'user': {'id': 'u3', 'name': 'Cy'},
          'cells': 3,
        },
      ],
      'taken_from_hidden': 2,
      'loop_count': 2,
      'kudos_count': 4,
      'kudos_by_me': true,
      'comment_count': 1,
      'status': 'accepted',
    };

PagedResult<T> page<T>(List<T> items, [String? next]) => PagedResult<T>(items: items, nextCursor: next);

UserListItem person(String id, {String? name, bool following = false, bool followsMe = false}) =>
    UserListItem(id: id, name: name ?? 'User $id', isFollowing: following, followsMe: followsMe);

Comment comment(String id, {String author = 'u2', String authorName = 'Bob', String text = 'Nice', bool canDelete = false}) =>
    Comment(
      id: id,
      runId: 'r1',
      user: UserRef(id: author, name: authorName),
      text: text,
      createdAt: 1700000100000,
      canDelete: canDelete,
    );

AppNotification note(
  String id,
  String type, {
  bool read = false,
  UserRef? actor = const UserRef(id: 'u2', name: 'Bob'),
  int? cells,
  int? unattributed,
  String? runId,
  String? preview,
}) =>
    AppNotification(
      id: id,
      type: type,
      createdAt: 1700000200000,
      read: read,
      actor: actor,
      cells: cells,
      cellsUnattributed: unattributed,
      runId: runId,
      commentPreview: preview,
    );

const List<LatLngPoint> hexBoundary = [
  LatLngPoint(50.001, 8.7),
  LatLngPoint(50.0005, 8.701),
  LatLngPoint(49.9995, 8.701),
  LatLngPoint(49.999, 8.7),
  LatLngPoint(49.9995, 8.699),
  LatLngPoint(50.0005, 8.699),
];

LostCell lost(String id, {UserRef? to, int lostAt = 1700000000000}) =>
    LostCell(cell: id, lat: 50.0, lng: 8.7, boundary: hexBoundary, lostAt: lostAt, lostTo: to);
