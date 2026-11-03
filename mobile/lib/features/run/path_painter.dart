import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'run_controller.dart';

/// Draws the recorded path scaled to fit the box (no map tiles needed).
class PathPainter extends CustomPainter {
  PathPainter(this.points, this.color);

  final List<PathPoint> points;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2) return;
    var minLat = points.first.lat, maxLat = points.first.lat;
    var minLng = points.first.lng, maxLng = points.first.lng;
    for (final p in points) {
      minLat = math.min(minLat, p.lat);
      maxLat = math.max(maxLat, p.lat);
      minLng = math.min(minLng, p.lng);
      maxLng = math.max(maxLng, p.lng);
    }
    final midLat = (minLat + maxLat) / 2;
    final xScale = math.cos(midLat * math.pi / 180);
    final spanX = math.max((maxLng - minLng) * xScale, 1e-9);
    final spanY = math.max(maxLat - minLat, 1e-9);
    const pad = 16.0;
    final w = math.max(size.width - 2 * pad, 1.0);
    final h = math.max(size.height - 2 * pad, 1.0);
    final scale = math.min(w / spanX, h / spanY);
    final offX = pad + (w - spanX * scale) / 2;
    final offY = pad + (h - spanY * scale) / 2;

    Offset project(PathPoint p) => Offset(
          offX + (p.lng - minLng) * xScale * scale,
          offY + (maxLat - p.lat) * scale,
        );

    final path = Path()..moveTo(project(points.first).dx, project(points.first).dy);
    for (final p in points.skip(1)) {
      final o = project(p);
      path.lineTo(o.dx, o.dy);
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
    final end = project(points.last);
    canvas.drawCircle(end, 7, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant PathPainter old) =>
      old.points.length != points.length || old.color != color;
}
