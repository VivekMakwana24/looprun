import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:looprun/domain/recorder/geo.dart';
import 'package:looprun/domain/recorder/loop_gap.dart';

/// Metres east (x) and north (y) of a point near Frankfurt, as a path point.
PathPoint at(double x, double y) {
  const mPerDegLat = earthRadiusM * math.pi / 180.0;
  final mPerDegLng = mPerDegLat * math.cos(50.0 * math.pi / 180.0);
  return PathPoint(50.0 + y / mPerDegLat, 8.7 + x / mPerDegLng);
}

/// A path through the corners with a point every 20 m, like a GPS track.
List<PathPoint> track(List<List<double>> corners) {
  final out = <PathPoint>[at(corners.first[0], corners.first[1])];
  for (var c = 1; c < corners.length; c++) {
    final ax = corners[c - 1][0], ay = corners[c - 1][1];
    final bx = corners[c][0], by = corners[c][1];
    final len = math.sqrt((bx - ax) * (bx - ax) + (by - ay) * (by - ay));
    final steps = (len / 20).round();
    for (var i = 1; i <= steps; i++) {
      out.add(at(ax + (bx - ax) * i / steps, ay + (by - ay) * i / steps));
    }
  }
  return out;
}

void main() {
  group('computeLoopProgress', () {
    test('no gap is given before the path is 150 m long', () {
      final p = buildLoopSketch(track([[0, 0], [100, 0]])).progress;
      expect(p.gapM, isNull);
      expect(p.closed, isFalse);
      expect(const LoopSketch().progress.gapM, isNull);
      expect(buildLoopSketch(const []).points, isEmpty);
      expect(buildLoopSketch([at(0, 0)]).progress.closed, isFalse);
    });

    test('on a straight road the gap is the way back to the start, not the road just behind', () {
      final p = buildLoopSketch(track([[0, 0], [1000, 0]])).progress;
      expect(p.closed, isFalse);
      expect(p.gapM, closeTo(1000, 5));
    });

    test('three sides of a square: the gap is the fourth side', () {
      final p = buildLoopSketch(track([[0, 0], [400, 0], [400, 400], [0, 400]])).progress;
      expect(p.closed, isFalse);
      expect(p.gapM, closeTo(400, 3));
      expect(p.target!.lat, closeTo(50.0, 1e-6));
    });

    test('140 m short of the start reads 140 m and is not closed', () {
      final p =
          buildLoopSketch(track([[0, 0], [400, 0], [400, 400], [0, 400], [0, 140]])).progress;
      expect(p.gapM, closeTo(140, 2));
      expect(p.closed, isFalse);
    });

    test('within 80 m of the earlier path the loop is closed', () {
      final p = buildLoopSketch(track([[0, 0], [400, 0], [400, 400], [0, 400], [0, 60]])).progress;
      expect(p.gapM, closeTo(60, 2));
      expect(p.closed, isTrue);
      expect(p.crossed, isFalse);
    });

    test('a path that crosses itself is closed even when the runner is far away again', () {
      final before =
          buildLoopSketch(track([[0, 0], [400, 0], [400, 410], [210, 410], [210, 210]])).progress;
      expect(before.crossed, isFalse);
      expect(before.closed, isFalse);
      final after =
          buildLoopSketch(track([[0, 0], [400, 0], [400, 410], [210, 410], [210, -390]])).progress;
      expect(after.crossed, isTrue);
      expect(after.closed, isTrue);
      expect(after.gapM, greaterThan(300));
    });

    test('a small wobble on the spot is not a crossing', () {
      final p = buildLoopSketch(track([[0, 0], [100, 0], [90, 5], [110, -5], [300, 0]])).progress;
      expect(p.crossed, isFalse);
      expect(p.closed, isFalse);
    });
  });

  group('downsamplePath', () {
    test('drops jitter closer than the spacing but keeps both ends', () {
      final jitter = [for (var i = 0; i < 200; i++) at(i % 2 == 0 ? 0.0 : 1.0, 0)];
      final thin = downsamplePath(jitter);
      expect(thin.length, 2);
      expect(thin.first.lng, jitter.first.lng);
      expect(thin.last.lng, jitter.last.lng);
    });

    test('never returns more than maxPoints and keeps the order', () {
      final long = track([[0, 0], [20000, 0]]);
      expect(long.length, 1001);
      final thin = downsamplePath(long, maxPoints: 100);
      expect(thin.length, lessThanOrEqualTo(100));
      expect(thin.first.lng, long.first.lng);
      expect(thin.last.lng, long.last.lng);
      for (var i = 1; i < thin.length; i++) {
        expect(thin[i].lng, greaterThan(thin[i - 1].lng));
      }
    });

    test('short paths come back unchanged', () {
      expect(downsamplePath(const []), isEmpty);
      expect(downsamplePath([at(0, 0), at(1, 0)]).length, 2);
    });
  });

  test('kmMarks marks every full kilometre', () {
    final marks = kmMarks(track([[0, 0], [2400, 0]]));
    expect(marks.length, 2);
    expect(haversineM(50.0, 8.7, marks[0].lat, marks[0].lng), closeTo(1000, 1));
    expect(haversineM(50.0, 8.7, marks[1].lat, marks[1].lng), closeTo(2000, 1));
    expect(kmMarks(track([[0, 0], [900, 0]])), isEmpty);
  });
}
