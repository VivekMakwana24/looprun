import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../domain/recorder/geo.dart';
import '../../domain/recorder/loop_gap.dart';

/// Colours of the loop picture (from the theme tokens).
class LoopPaintColors {
  const LoopPaintColors({
    required this.track,
    required this.text,
    required this.surface,
    required this.grid,
  });
  final Color track;
  final Color text;
  final Color surface;
  final Color grid;
}

/// "Your loop so far": a dotted grid, the track, km markers, the ringed start, a dashed line from where
/// the runner is to the nearest earlier point, and the runner as a dot with a halo. Drawn from the thinned
/// path of [LoopSketch], scaled to fit (no map tiles).
class LoopPainter extends CustomPainter {
  LoopPainter({required this.sketch, required this.colors, required this.labelStyle});

  final LoopSketch sketch;
  final LoopPaintColors colors;
  final TextStyle labelStyle;

  @override
  void paint(Canvas canvas, Size size) {
    final dot = Paint()..color = colors.grid;
    for (var y = 2.0; y < size.height; y += 16) {
      for (var x = 2.0; x < size.width; x += 16) {
        canvas.drawCircle(Offset(x, y), 1.2, dot);
      }
    }
    final pts = sketch.points;
    if (pts.isEmpty) return;

    var minLat = pts.first.lat, maxLat = pts.first.lat;
    var minLng = pts.first.lng, maxLng = pts.first.lng;
    for (final p in pts) {
      minLat = math.min(minLat, p.lat);
      maxLat = math.max(maxLat, p.lat);
      minLng = math.min(minLng, p.lng);
      maxLng = math.max(maxLng, p.lng);
    }
    final midLat = (minLat + maxLat) / 2;
    final xScale = math.cos(midLat * math.pi / 180);
    // At least about 100 m across, so a few metres of jitter at the start are not blown up to fill the box.
    const minSpanDeg = 0.0009;
    final spanX = math.max((maxLng - minLng) * xScale, minSpanDeg);
    final spanY = math.max(maxLat - minLat, minSpanDeg);
    const pad = 20.0;
    final w = math.max(size.width - 2 * pad, 1.0);
    final h = math.max(size.height - 2 * pad, 1.0);
    final scale = math.min(w / spanX, h / spanY);
    final offX = pad + (w - (maxLng - minLng) * xScale * scale) / 2;
    final offY = pad + (h - (maxLat - minLat) * scale) / 2;
    Offset project(PathPoint p) => Offset(
          offX + (p.lng - minLng) * xScale * scale,
          offY + (maxLat - p.lat) * scale,
        );

    if (pts.length >= 2) {
      final path = Path()..moveTo(project(pts.first).dx, project(pts.first).dy);
      for (final p in pts.skip(1)) {
        final o = project(p);
        path.lineTo(o.dx, o.dy);
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = colors.track
          ..style = PaintingStyle.stroke
          ..strokeWidth = 5
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );
    }

    final head = project(pts.last);
    final progress = sketch.progress;
    final target = progress.target;
    if (target != null && !progress.closed) {
      // Dotted line: where the loop would close.
      final to = project(target);
      final paint = Paint()
        ..color = colors.text
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round;
      final d = (to - head).distance;
      if (d > 0) {
        final dir = (to - head) / d;
        for (var t = 0.0; t <= d; t += 9) {
          canvas.drawCircle(head + dir * t, 1.5, paint);
        }
      }
    }

    final start = project(pts.first);
    canvas.drawCircle(start, 8, Paint()..color = colors.surface);
    canvas.drawCircle(
      start,
      8,
      Paint()
        ..color = colors.text
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );

    for (var i = 0; i < sketch.kmMarks.length; i++) {
      final o = project(sketch.kmMarks[i]);
      canvas.drawCircle(o, 10, Paint()..color = colors.surface);
      canvas.drawCircle(
        o,
        10,
        Paint()
          ..color = colors.track
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
      final tp = TextPainter(
        text: TextSpan(text: '${i + 1}', style: labelStyle.copyWith(color: colors.text)),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, o - Offset(tp.width / 2, tp.height / 2));
    }

    canvas.drawCircle(head, 15, Paint()..color = colors.track.withValues(alpha: 0.3));
    canvas.drawCircle(head, 8, Paint()..color = colors.track);
  }

  @override
  bool shouldRepaint(covariant LoopPainter old) =>
      !identical(old.sketch, sketch) || old.colors.track != colors.track || old.colors.text != colors.text;
}
