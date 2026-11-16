import 'dart:math' as math;

import 'geo.dart';

/// The loop counts as closed when the runner is this close to an earlier part of the path.
const double loopCloseWithinM = 80;

/// The newest stretch of path that is ignored when looking for "an earlier part" (otherwise the runner
/// would always be a few metres from where they were a second ago).
const double loopIgnoreRecentM = 150;

/// How far the run is from closing a loop. Pure Dart; only a hint for the runner. The server decides
/// which loops really count.
class LoopProgress {
  const LoopProgress({this.closed = false, this.gapM, this.target, this.crossed = false});

  /// True when the runner is within [loopCloseWithinM] of an earlier part of the path, or the path
  /// has crossed itself.
  final bool closed;

  /// Metres from the current position to the nearest earlier track point; null while the path is
  /// shorter than [loopIgnoreRecentM] (there is no "earlier part" yet).
  final double? gapM;

  /// That nearest earlier point (where the dashed line is drawn to).
  final PathPoint? target;

  /// True when the path has crossed itself somewhere.
  final bool crossed;
}

/// The run so far, thinned for drawing, with what the picture needs.
class LoopSketch {
  const LoopSketch({
    this.points = const [],
    this.kmMarks = const [],
    this.progress = const LoopProgress(),
  });

  /// The path, at most a few hundred points.
  final List<PathPoint> points;

  /// Where each full kilometre was reached (index 0 = 1 km).
  final List<PathPoint> kmMarks;
  final LoopProgress progress;

  PathPoint? get start => points.isEmpty ? null : points.first;
  PathPoint? get head => points.isEmpty ? null : points.last;
}

/// Drops points closer than [minSpacingM] to the last kept one (GPS jitter while standing still), then
/// keeps at most [maxPoints] evenly. The first and the last point always stay.
List<PathPoint> downsamplePath(
  List<PathPoint> path, {
  double minSpacingM = 8,
  int maxPoints = 400,
}) {
  if (path.length <= 2) return List<PathPoint>.of(path);
  final spaced = <PathPoint>[path.first];
  for (var i = 1; i < path.length - 1; i++) {
    final p = path[i];
    final k = spaced.last;
    if (haversineM(k.lat, k.lng, p.lat, p.lng) >= minSpacingM) spaced.add(p);
  }
  spaced.add(path.last);
  if (maxPoints < 2 || spaced.length <= maxPoints) return spaced;
  final out = <PathPoint>[];
  final step = (spaced.length - 1) / (maxPoints - 1);
  var lastIndex = -1;
  for (var k = 0; k < maxPoints; k++) {
    final i = k == maxPoints - 1 ? spaced.length - 1 : (k * step).floor();
    if (i == lastIndex) continue;
    out.add(spaced[i]);
    lastIndex = i;
  }
  return out;
}

List<double> _cumulative(List<PathPoint> pts) {
  final cum = List<double>.filled(pts.length, 0);
  for (var i = 1; i < pts.length; i++) {
    cum[i] = cum[i - 1] + haversineM(pts[i - 1].lat, pts[i - 1].lng, pts[i].lat, pts[i].lng);
  }
  return cum;
}

/// Where each full kilometre of [path] was reached, interpolated between the two points around it.
List<PathPoint> kmMarks(List<PathPoint> path) {
  final marks = <PathPoint>[];
  var travelled = 0.0;
  var next = 1000.0;
  for (var i = 1; i < path.length; i++) {
    final a = path[i - 1];
    final b = path[i];
    final d = haversineM(a.lat, a.lng, b.lat, b.lng);
    while (d > 0 && travelled + d >= next) {
      final f = (next - travelled) / d;
      marks.add(PathPoint(a.lat + (b.lat - a.lat) * f, a.lng + (b.lng - a.lng) * f));
      next += 1000.0;
    }
    travelled += d;
  }
  return marks;
}

double _cross(double ax, double ay, double bx, double by, double cx, double cy) =>
    (bx - ax) * (cy - ay) - (by - ay) * (cx - ax);

/// True when segment a-b properly crosses segment c-d (touching end points do not count).
bool _segmentsCross(
  double ax, double ay, double bx, double by, double cx, double cy, double dx, double dy,
) {
  final d1 = _cross(cx, cy, dx, dy, ax, ay);
  final d2 = _cross(cx, cy, dx, dy, bx, by);
  final d3 = _cross(ax, ay, bx, by, cx, cy);
  final d4 = _cross(ax, ay, bx, by, dx, dy);
  return ((d1 > 0 && d2 < 0) || (d1 < 0 && d2 > 0)) && ((d3 > 0 && d4 < 0) || (d3 < 0 && d4 > 0));
}

/// Loop progress for a path that is already thinned (see [downsamplePath]).
///
/// The gap is the straight-line distance from the last point to the nearest earlier point that lies at
/// least [ignoreRecentM] back along the path and that the path left and came back towards (the path
/// between them is at least [detourFactor] times the straight line; the start always qualifies). The path "crosses itself" when two of its segments intersect
/// and are at least [ignoreRecentM] of path apart (so a wobble does not count).
LoopProgress computeLoopProgress(
  List<PathPoint> pts, {
  double ignoreRecentM = loopIgnoreRecentM,
  double closeWithinM = loopCloseWithinM,
  double detourFactor = 2.0,
}) {
  final n = pts.length;
  if (n < 2) return const LoopProgress();
  final cum = _cumulative(pts);
  final total = cum[n - 1];

  // Last index that is far enough back along the path.
  var cutoff = -1;
  for (var i = n - 2; i >= 0; i--) {
    if (total - cum[i] >= ignoreRecentM) {
      cutoff = i;
      break;
    }
  }
  if (cutoff < 0) return const LoopProgress();

  final head = pts[n - 1];
  var gap = double.infinity;
  PathPoint? target;
  for (var i = 0; i <= cutoff; i++) {
    final d = haversineM(head.lat, head.lng, pts[i].lat, pts[i].lng);
    // The start always counts. Any other point only counts when the runner took a real detour to get
    // from it to here; otherwise, on a straight road, the "nearest earlier point" would simply be the
    // road 150 m behind and the gap would read 150 m for ever.
    final detour = i == 0 || (total - cum[i]) >= detourFactor * d;
    if (detour && d < gap) {
      gap = d;
      target = pts[i];
    }
  }

  // Flat coordinates in metres around the first point: good enough for a run.
  final lat0 = pts[0].lat;
  final lng0 = pts[0].lng;
  final mPerDegLat = earthRadiusM * math.pi / 180.0;
  final mPerDegLng = mPerDegLat * math.cos(lat0 * math.pi / 180.0);
  final xs = List<double>.generate(n, (i) => (pts[i].lng - lng0) * mPerDegLng);
  final ys = List<double>.generate(n, (i) => (pts[i].lat - lat0) * mPerDegLat);
  var crossed = false;
  for (var j = n - 2; j >= 1 && !crossed; j--) {
    for (var i = 0; i + 1 < j; i++) {
      if (cum[j] - cum[i + 1] < ignoreRecentM) break; // later i are even closer along the path
      if (_segmentsCross(xs[i], ys[i], xs[i + 1], ys[i + 1], xs[j], ys[j], xs[j + 1], ys[j + 1])) {
        crossed = true;
        break;
      }
    }
  }

  return LoopProgress(
    closed: crossed || gap <= closeWithinM,
    gapM: gap,
    target: target,
    crossed: crossed,
  );
}

/// Everything the "your loop so far" picture and its caption need, from the raw recorded path.
LoopSketch buildLoopSketch(List<PathPoint> path) {
  if (path.isEmpty) return const LoopSketch();
  final pts = downsamplePath(path);
  return LoopSketch(points: pts, kmMarks: kmMarks(pts), progress: computeLoopProgress(pts));
}
