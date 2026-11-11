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
    expect(CellChange.tryParse({'type': 'ping'}), isNull);
    expect(CellChange.tryParse('nope'), isNull);
    expect(CellChange.tryParse({'type': 'cell_changed', 'cell': 'x'}), isNull);
  });
}
