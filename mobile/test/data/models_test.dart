import 'package:flutter_test/flutter_test.dart';
import 'package:looprun/core/format.dart';
import 'package:looprun/data/models/models.dart';

void main() {
  liveFrameTests();
  test('RunStatus parses a processing response with nulls', () {
    final s = RunStatus.fromJson({
      'id': 'abc',
      'status': 'processing',
      'distance_m': null,
      'moving_seconds': null,
    });
    expect(s.isProcessing, isTrue);
    expect(s.distanceM, isNull);
    expect(s.loops, isEmpty);
    expect(s.cellsClaimed, 0);
  });

  test('RunStatus parses a full accepted response and round-trips', () {
    final json = {
      'id': 'abc',
      'status': 'accepted',
      'distance_m': 4200.5,
      'moving_seconds': 1500,
      'loops': [
        {'cells': 12, 'area_km2': 0.31}
      ],
      'cells_claimed': 12,
      'cells_taken_from_others': 3,
      'flags': [
        {'code': 'near_closure_repaired', 'severity': 'soft', 'detail': 'joined'}
      ],
    };
    final s = RunStatus.fromJson(json);
    expect(s.status, RunStatus.accepted);
    expect(s.distanceM, 4200.5);
    expect(s.movingSeconds, 1500);
    expect(s.loops.single.cells, 12);
    expect(s.loops.single.areaKm2, 0.31);
    expect(s.cellsTakenFromOthers, 3);
    expect(s.flags.single.isHard, isFalse);
    final again = RunStatus.fromJson(s.toJson());
    expect(again.cellsClaimed, 12);
    expect(again.flags.single.code, 'near_closure_repaired');
  });

  test('integer distance is accepted as a number', () {
    final s = RunStatus.fromJson({'id': 'a', 'status': 'accepted', 'distance_m': 1000});
    expect(s.distanceM, 1000.0);
  });

  test('hard flag is detected', () {
    final f = Flag.fromJson({'code': 'mock_location', 'severity': 'hard', 'detail': ''});
    expect(f.isHard, isTrue);
  });

  test('Cell parses owner, hidden and mine', () {
    final mine = Cell.fromJson({
      'id': '8a1f',
      'lat': 50.1,
      'lng': 8.7,
      'owner': {'id': 'u1', 'name': 'Ann'},
      'mine': true,
      'hidden': false,
    });
    expect(mine.mine, isTrue);
    expect(mine.lat, 50.1);
    expect(mine.lng, 8.7);
    expect(mine.owner!.name, 'Ann');
    final hidden = Cell.fromJson({'id': '8a20', 'owner': null, 'mine': false, 'hidden': true});
    expect(hidden.owner, isNull);
    expect(hidden.hidden, isTrue);
  });

  test('Cell parses the hexagon boundary and the strength of an own cell (D10)', () {
    final mine = Cell.fromJson({
      'id': 'a',
      'lat': 50.0,
      'lng': 8.7,
      'boundary': [
        [50.001, 8.7], [50.0005, 8.701], [49.9995, 8.701], [49.999, 8.7], [49.9995, 8.699], [50.0005, 8.699],
      ],
      'owner': {'id': 'u1', 'name': 'Ann'},
      'mine': true,
      'strength': 0.3,
    });
    expect(mine.boundary.length, 6);
    expect(mine.boundary.first, const LatLngPoint(50.001, 8.7));
    expect(mine.strength, 0.3);
    expect(mine.isFading, isTrue);

    final strong = Cell.fromJson({'id': 'b', 'mine': true, 'strength': 0.5});
    expect(strong.isFading, isFalse);
    expect(strong.boundary, isEmpty);

    // Strength is never taken for somebody else's cell, whatever arrives.
    final other = Cell.fromJson({
      'id': 'c',
      'owner': {'id': 'u2', 'name': 'Bob'},
      'mine': false,
      'strength': 0.1,
    });
    expect(other.strength, isNull);
    expect(other.isFading, isFalse);

    // A malformed boundary is dropped (the map then draws a circle).
    expect(Cell.fromJson({'id': 'd', 'boundary': [[1, 2], [3]]}).boundary, isEmpty);
    expect(Cell.fromJson({'id': 'e', 'boundary': 'x'}).boundary, isEmpty);
    expect(Cell.fromJson({'id': 'f', 'mine': true}).strength, isNull);
    expect(Cell.fromJson({'id': 'g', 'mine': true, 'strength': 7}).strength, 1.0);
  });

  test('Leaderboard parses me, with and without a rank (D10)', () {
    final b = Leaderboard.fromJson({
      'week': '2026-W47',
      'entries': <Object>[],
      'me': {'rank': 4, 'cells': 128},
    });
    expect(b.me, const LeaderboardMe(rank: 4, cells: 128));
    final none = Leaderboard.fromJson({
      'week': '2026-W47',
      'entries': <Object>[],
      'me': {'rank': null, 'cells': 0},
    });
    expect(none.me!.rank, isNull);
    expect(none.me!.cells, 0);
    expect(Leaderboard.fromJson({'week': 'x', 'entries': <Object>[]}).me, isNull);
  });

  test('MeInfo and FreezeStatus parse GET /me (D10)', () {
    final me = MeInfo.fromJson({
      'user': {'id': 'u1', 'name': 'Ann'},
      'home_zones': [
        {'lat': 1.0, 'lng': 2.0, 'radius_m': 300}
      ],
      'freeze': {'freeze_until': null, 'used_days': 12, 'quota_days': 30, 'window_days': 90},
    });
    expect(me.user.name, 'Ann');
    expect(me.homeZones.single.radiusM, 300);
    expect(me.freeze.freezeUntil, isNull);
    expect(me.freeze.usedDays, 12);
    expect(me.freeze.quotaDays, 30);
    expect(me.freeze.windowDays, 90);
    expect(me.freeze.hasQuota, isTrue);
    // An older server answers POST /me/freeze with freeze_until only.
    final old = FreezeStatus.fromJson({'freeze_until': 99});
    expect(old.freezeUntil, 99);
    expect(old.hasQuota, isFalse);
  });

  test('Session parses token and user', () {
    final s = Session.fromJson({
      'access_token': 't0k',
      'user': {'id': 'u1', 'name': 'dev'},
    });
    expect(s.accessToken, 't0k');
    expect(s.user.name, 'dev');
  });

  test('Leaderboard parses entries', () {
    final b = Leaderboard.fromJson({
      'week': '2026-W45',
      'entries': [
        {
          'rank': 1,
          'user': {'id': 'u1', 'name': 'Ann'},
          'cells': 40
        }
      ],
    });
    expect(b.week, '2026-W45');
    expect(b.entries.single.cells, 40);
    expect(b.entries.single.user.name, 'Ann');
  });

  test('RunUpload serialises to the contract shape', () {
    const up = RunUpload(
      id: '11111111-1111-4111-8111-111111111111',
      startedAt: 1000,
      endedAt: 2000,
      fixes: [Fix(lat: 50.0, lng: 8.7, t: 1500, acc: 4.5, mock: true)],
    );
    final j = up.toJson();
    expect(j['id'], '11111111-1111-4111-8111-111111111111');
    expect(j['started_at'], 1000);
    expect(j['ended_at'], 2000);
    final fix = (j['fixes'] as List).single as Map<String, dynamic>;
    expect(fix, {'lat': 50.0, 'lng': 8.7, 't': 1500, 'acc': 4.5, 'mock': true});
  });

  test('HomeZone serialises radius_m', () {
    expect(const HomeZone(lat: 1, lng: 2, radiusM: 200).toJson(),
        {'lat': 1.0, 'lng': 2.0, 'radius_m': 200.0});
  });

  test('formatters', () {
    expect(formatDistance(850), '850 m');
    expect(formatDistance(1234), '1.23 km');
    expect(formatDuration(65000), '01:05');
    expect(formatDuration(3725000), '1:02:05');
    expect(formatKm(3420), '3.42');
    expect(formatPace(370000, 1000), '6:10');
    expect(formatPace(10000, 20), noValue, reason: 'too short to say');
    expect(formatPace(0, 1000), noValue);
    expect(formatPace(7200000, 100), noValue, reason: 'standing around is not a pace');
    expect(formatWeekLabel('2026-W47'), 'WEEK 47');
    expect(formatWeekLabel('2026-W05'), 'WEEK 5');
    expect(formatWeekLabel('soon'), isNull);
    expect(formatRunDate(DateTime(2026, 11, 16, 6, 42)), 'Mon 16 Nov, 06:42');
    expect(formatDayMonth(DateTime(2026, 1, 3)), '3 Jan');
  });
}

void liveFrameTests() {
  test('CellChange parses a cell_changed frame', () {
    final c = CellChange.tryParse({
      'type': 'cell_changed',
      'cell': '8a1f',
      'lat': 50.1,
      'lng': 8.6,
      'owner': {'id': 'u1', 'name': 'Ann'},
      'mine': true,
    });
    expect(c!.id, '8a1f');
    expect(c.owner!.name, 'Ann');
    expect(c.mine, isTrue);
    expect(c.toCell().hidden, isFalse);
  });

  test('CellChange without owner becomes a hidden cell; junk is ignored', () {
    final c = CellChange.tryParse({
      'type': 'cell_changed',
      'cell': 'x',
      'lat': 1,
      'lng': 2,
      'owner': null,
      'mine': false,
    });
    expect(c!.toCell().hidden, isTrue);
    final own = CellChange.tryParse({
      'type': 'cell_changed',
      'cell': 'y',
      'lat': 1,
      'lng': 2,
      'boundary': [
        [1.0, 2.0], [1.1, 2.0], [1.1, 2.1],
      ],
      'owner': {'id': 'u1', 'name': 'Ann'},
      'mine': true,
      'strength': 0.25,
    })!;
    expect(own.toCell().boundary.length, 3);
    expect(own.toCell().strength, 0.25);
    expect(own.toCell().isFading, isTrue);
    expect(own.toCell().hidden, isFalse);
    expect(CellChange.tryParse({'type': 'ping'}), isNull);
    expect(CellChange.tryParse('nope'), isNull);
    expect(CellChange.tryParse({'type': 'cell_changed', 'cell': 'x'}), isNull);
  });
}
