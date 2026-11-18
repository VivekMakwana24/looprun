import 'package:flutter_test/flutter_test.dart';
import 'package:looprun/data/models/api_exception.dart';
import 'package:looprun/data/models/social_models.dart';

import '../fakes/social_fixtures.dart';

void main() {
  test('a run card reads every field of the contract and defaults the rest', () {
    final c = RunCard.fromJson(cardJson('r1'));
    expect(c.id, 'r1');
    expect(c.user.name, 'Bob');
    expect(c.distanceM, 5200);
    expect(c.movingSeconds, 1650);
    expect(c.paceSecPerKm, closeTo(317.3, 0.001));
    expect(c.cellsClaimed, 14);
    expect(c.cellsTaken, 5);
    expect(c.takenFrom.single.user.name, 'Cy');
    expect(c.takenFrom.single.cells, 3);
    expect(c.takenFromHidden, 2);
    expect(c.loopCount, 2);
    expect(c.kudosCount, 4);
    expect(c.kudosByMe, isTrue);
    expect(c.commentCount, 1);
    expect(c.isAccepted, isTrue);

    final bare = RunCard.fromJson({'id': 'r2', 'user': {'id': 'u', 'name': 'N'}, 'started_at': 5, 'status': 'processing'});
    expect(bare.distanceM, isNull);
    expect(bare.movingSeconds, isNull);
    expect(bare.paceSecPerKm, isNull);
    expect(bare.cellsClaimed, 0);
    expect(bare.takenFrom, isEmpty);
    expect(bare.isProcessing, isTrue);
  });

  test('a card has no field for a route, a polygon or a start point', () {
    // The model is the app's guarantee: even if a server sent them, nothing reads them.
    final c = RunCard.fromJson({...cardJson('r1'), 'fixes': [1], 'polygon': [2], 'start': {'lat': 1, 'lng': 2}});
    expect(c.toString(), isNot(contains('polygon')));
    expect(c.id, 'r1');
  });

  test('copyWith changes only kudos and comment numbers', () {
    final c = card('r1', kudos: 1).copyWith(kudosCount: 2, kudosByMe: true, commentCount: 3);
    expect(c.kudosCount, 2);
    expect(c.kudosByMe, isTrue);
    expect(c.commentCount, 3);
    expect(c.cellsClaimed, 14);
  });

  test('profile, follow state, kudos state, comment', () {
    final p = Profile.fromJson({
      'id': 'u2',
      'name': 'Bob',
      'cells_held': 40,
      'weekly_rank': null,
      'followers_count': 3,
      'following_count': 4,
      'joined_at': 1700000000000,
      'is_me': false,
      'is_following': true,
      'follows_me': true,
    });
    expect(p.weeklyRank, isNull);
    expect(p.isFollowing, isTrue);
    expect(p.withFollow(const FollowState(isFollowing: false, followersCount: 2)).followersCount, 2);
    expect(KudosState.fromJson({'kudos_by_me': true, 'kudos_count': 2}), const KudosState(kudosByMe: true, kudosCount: 2));
    final c = Comment.fromJson({
      'id': 'c1',
      'run_id': 'r1',
      'user': {'id': 'u2', 'name': 'Bob'},
      'text': 'hi',
      'created_at': 9,
      'hidden': true,
      'can_delete': true,
    });
    expect(c.hidden, isTrue);
    expect(c.canDelete, isTrue);
  });

  test('battle models', () {
    final r = Rivalry.fromJson({
      'days': 30,
      'rivals': [
        {
          'user': {'id': 'u2', 'name': 'Bob'},
          'taken': 5,
          'lost': 2,
          'net': 3,
          'last_battle_at': 77,
          'is_following': true,
        }
      ],
      'unattributed': {'taken': 1, 'lost': 4},
    });
    expect(r.rivals.single.net, 3);
    expect(r.unattributed.lost, 4);
    final s = BattleSummary.fromJson({'taken': 7, 'lost': 2, 'battles': 3});
    expect(s.net, 5, reason: 'worked out when the server leaves it out');
    final l = LostCell.fromJson({
      'cell': 'abc',
      'lat': 50.0,
      'lng': 8.7,
      'boundary': [
        [50.001, 8.7],
        [50.0005, 8.701],
        [49.9995, 8.701],
        [49.999, 8.7],
        [49.9995, 8.699],
        [50.0005, 8.699],
      ],
      'lost_at': 5,
      'lost_to': null,
    });
    expect(l.boundary.length, 6);
    expect(l.lostTo, isNull);
  });

  test('notifications and their page', () {
    final p = NotificationPage.fromJson({
      'items': [
        {
          'id': 'n1',
          'type': 'cells_taken',
          'created_at': 5,
          'read': false,
          'actor': null,
          'cells': 0,
          'cells_unattributed': 7,
        }
      ],
      'next_cursor': 'c2',
      'unread_count': 9,
    });
    expect(p.unreadCount, 9);
    expect(p.nextCursor, 'c2');
    expect(p.items.single.actor, isNull);
    expect(p.items.single.cellsUnattributed, 7);
    expect(p.items.single.asRead().read, isTrue);
  });

  test('a paged result without next_cursor is the last page', () {
    final r = PagedResult.fromJson({'items': [cardJson('r1')]}, RunCard.fromJson);
    expect(r.hasMore, isFalse);
    expect(r.items.length, 1);
  });

  test('friendly messages for the codes of the contract', () {
    expect(const ApiException(409, 'x', code: 'follow_limit').friendlyMessage, contains('500'));
    expect(const ApiException(409, 'x', code: 'comment_limit').friendlyMessage, contains('200'));
    expect(const ApiException(422, 'x', code: 'own_run').friendlyMessage, contains('own run'));
    expect(const ApiException(422, 'x', code: 'name_rejected').friendlyMessage, contains('name'));
    expect(const ApiException(404, 'x').friendlyMessage, contains('not available'));
    expect(const ApiException(429, 'x').friendlyMessage, contains('Wait'));
    expect(const ApiException(503, 'x').friendlyMessage, contains('busy'));
    expect(const ApiException(null, 'x').friendlyMessage, contains('connection'));
    expect(const ApiException.malformed('x').friendlyMessage, contains('cannot read'));
    expect(const ApiException(404, 'raw server text').friendlyMessage, isNot(contains('raw server text')));
  });
}
