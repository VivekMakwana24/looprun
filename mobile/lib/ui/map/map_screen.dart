import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/format.dart';
import '../../core/routes.dart';
import '../../core/theme.dart';
import '../../data/models/models.dart';
import '../../domain/recorder/run_recorder.dart';
import '../core/report_dialog.dart';
import '../core/widgets.dart';
import '../leaderboard/leaderboard_view_model.dart';
import '../run/run_view_model.dart';
import 'cell_map.dart';
import 'map_view_model.dart';

/// Fires when "centre the map on me" is pressed.
class _Signal extends ChangeNotifier {
  void fire() => notifyListeners();
}

/// Lane 1: the map with the cells, the week's numbers and the start button.
class MapScreen extends ConsumerStatefulWidget {
  const MapScreen({super.key});

  @override
  ConsumerState<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends ConsumerState<MapScreen> {
  final _Signal _recenter = _Signal();
  bool _starting = false;

  @override
  void dispose() {
    _recenter.dispose();
    super.dispose();
  }

  void _toast(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _onCellTap(Cell cell) async {
    if (!mounted) return;
    final String who;
    if (cell.mine) {
      who = cell.isFading
          ? 'This cell is yours, but it is fading. Run through it again to hold it.'
          : 'This cell is yours.';
    } else if (cell.hidden || cell.owner == null) {
      who = 'The owner of this cell is private.';
    } else {
      who = 'Held by ${cell.owner!.name}.';
    }
    final report = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cell'),
        content: Text(who),
        actions: [
          TextButton(
            key: const Key('report_cell_button'),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Report this cell'),
          ),
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Close')),
        ],
      ),
    );
    if (report != true || !mounted) return;
    final reason = await askReportReason(context, title: 'Report this cell');
    if (reason == null || !mounted) return;
    final message = await ref.read(mapViewModelProvider.notifier).reportCell(cell.id, reason);
    _toast(message);
  }

  /// START RUN: asks for permission and starts recording, then opens the live run screen.
  /// While a run is active the same button leads back to it.
  Future<void> _startOrOpenRun() async {
    final run = ref.read(runViewModelProvider);
    if (run.isActive || run.status == RecorderStatus.stopping) {
      context.push(recordPath);
      return;
    }
    if (_starting) return;
    setState(() => _starting = true);
    try {
      await ref.read(runViewModelProvider.notifier).start();
    } finally {
      if (mounted) setState(() => _starting = false);
    }
    if (!mounted) return;
    if (ref.read(runViewModelProvider).isActive) context.push(recordPath);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.lr;
    final top = MediaQuery.of(context).padding.top;
    final showMap = ref.watch(mapCanvasEnabledProvider);
    return Stack(
      children: [
        Positioned.fill(
          child: showMap
              ? CellMap(
                  recenter: _recenter,
                  onCellTap: _onCellTap,
                  onNoPosition: () => _toast('Allow location for Looprun to centre the map on you.'),
                )
              : ColoredBox(color: c.map),
        ),
        // Fade from the background colour so the numbers stay readable over the map.
        Positioned(
          left: 0,
          right: 0,
          top: 0,
          height: 210 + top,
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [c.bg, c.bg, c.bg.withValues(alpha: 0)],
                  stops: const [0, 0.38, 1],
                ),
              ),
            ),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          top: top,
          child: const IgnorePointer(child: _TopStats()),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (showMap)
                Align(
                  alignment: Alignment.centerRight,
                  child: Padding(
                    padding: const EdgeInsets.only(right: 16, bottom: 16),
                    child: LrIconButton(
                      key: const Key('recenter_button'),
                      icon: Icons.my_location,
                      semanticLabel: 'Centre the map on me',
                      filled: true,
                      onTap: _recenter.fire,
                    ),
                  ),
                ),
              _Sheet(starting: _starting, onStart: _startOrOpenRun),
            ],
          ),
        ),
      ],
    );
  }
}

/// Logo, week chip, the two numbers and the legend.
class _TopStats extends ConsumerWidget {
  const _TopStats();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.lr;
    final standing = ref.watch(myStandingProvider);
    final week = standing.week == null ? null : formatWeekLabel(standing.week!);
    final rank = standing.rank;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(Icons.refresh, size: 26, color: c.accentText),
              const SizedBox(width: 8),
              Text('LOOPRUN', style: LrText.display(24, color: c.text, tracking: 0.04, height: 1)),
              const Spacer(),
              if (week != null) WeekChip(label: week),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              LrStat(
                key: const Key('stat_cells_held'),
                value: standing.cells == null ? noValue : '${standing.cells}',
                label: 'CELLS HELD',
                accent: true,
              ),
              const SizedBox(width: 28),
              LrStat(
                key: const Key('stat_rank'),
                value: rank == null ? noValue : '#$rank',
                label: 'THIS WEEK',
              ),
            ],
          ),
          const SizedBox(height: 14),
          const _Legend(),
        ],
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend();

  @override
  Widget build(BuildContext context) {
    final c = context.lr;
    Widget item(Widget swatch, String label) => Padding(
          padding: const EdgeInsets.only(right: 14),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              swatch,
              const SizedBox(width: 6),
              Text(label, style: LrText.body(13, weight: FontWeight.w500, color: c.text2)),
            ],
          ),
        );
    Widget solid(Color color) => Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3)),
        );
    return Row(
      children: [
        item(solid(c.accent), 'Yours'),
        item(solid(c.rival), 'Others'),
        item(
          SizedBox(
            width: 10,
            height: 10,
            child: CustomPaint(painter: DashedBorderPainter(color: c.hidLine, radius: 3)),
          ),
          'Private',
        ),
      ],
    );
  }
}

/// A dashed rounded outline (the "Private" look: legend swatch, home-zone ring).
class DashedBorderPainter extends CustomPainter {
  DashedBorderPainter({
    required this.color,
    this.radius = 3,
    this.strokeWidth = 1.5,
    this.dash = 2.5,
    this.circle = false,
  });

  final Color color;
  final double radius;
  final double strokeWidth;
  final double dash;
  final bool circle;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(strokeWidth / 2);
    final path = Path();
    if (circle) {
      path.addOval(rect);
    } else {
      path.addRRect(RRect.fromRectAndRadius(rect, Radius.circular(radius)));
    }
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;
    for (final metric in path.computeMetrics()) {
      var d = 0.0;
      while (d < metric.length) {
        final end = d + dash < metric.length ? d + dash : metric.length;
        canvas.drawPath(metric.extractPath(d, end), paint);
        d += dash * 2;
      }
    }
  }

  @override
  bool shouldRepaint(covariant DashedBorderPainter old) =>
      old.color != color || old.radius != radius || old.strokeWidth != strokeWidth || old.circle != circle;
}

/// The bottom sheet: notices, the start button and the hint line.
class _Sheet extends ConsumerWidget {
  const _Sheet({required this.starting, required this.onStart});
  final bool starting;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.lr;
    final map = ref.watch(mapViewModelProvider);
    final run = ref.watch(runViewModelProvider);
    final uploads = ref.watch(uploadSummaryProvider);
    final fading = map.fadingCount;
    final active = run.isActive || run.status == RecorderStatus.stopping;
    final error = run.error;

    return Container(
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        border: Border(top: BorderSide(color: c.line)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (map.offline) ...[const OfflineBanner(), const SizedBox(height: 12)],
          if (!uploads.isEmpty) ...[
            _NoticeRow(
              key: const Key('upload_notice'),
              leading: Icon(
                uploads.failed > 0 ? Icons.error_outline : Icons.cloud_upload_outlined,
                size: 22,
                color: uploads.failed > 0 ? c.danger : c.muted,
              ),
              title: uploads.failed > 0
                  ? (uploads.failed == 1 ? '1 run was not uploaded' : '${uploads.failed} runs were not uploaded')
                  : (uploads.waiting == 1
                      ? '1 run is waiting to upload'
                      : '${uploads.waiting} runs are waiting to upload'),
              subtitle: uploads.failed > 0
                  ? 'Open it to try again. It is saved on this phone.'
                  : (uploads.retrying
                      ? 'No connection yet. Saved on this phone; we keep trying.'
                      : 'Saved on this phone. Sending now.'),
              onTap: uploads.runId == null ? null : () => context.push(runResultPath(uploads.runId!)),
            ),
            const SizedBox(height: 12),
          ],
          if (fading > 0) ...[
            _NoticeRow(
              key: const Key('fading_notice'),
              leading: const _FadingHexes(),
              title: fading == 1 ? '1 cell is fading' : '$fading cells are fading',
              subtitle: fading == 1 ? 'Run through it again to hold it' : 'Run through them again to hold them',
            ),
            const SizedBox(height: 12),
          ] else if (map.loadFailed) ...[
            _NoticeRow(
              key: const Key('map_error_notice'),
              leading: Icon(Icons.error_outline, size: 22, color: c.danger),
              title: map.offline ? 'Cells could not be loaded' : (map.notice ?? 'Cells could not be loaded'),
              subtitle: 'Tap to try again',
              onTap: () => ref.read(mapViewModelProvider.notifier).retry(),
            ),
            const SizedBox(height: 12),
          ] else if (map.loading) ...[
            _NoticeRow(
              key: const Key('map_loading_notice'),
              leading: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2.5, color: c.accent),
              ),
              title: 'Loading cells',
              subtitle: 'Looking up who holds this area',
            ),
            const SizedBox(height: 12),
          ] else if (map.notice != null) ...[
            _NoticeRow(
              key: const Key('map_notice'),
              leading: Icon(Icons.hexagon_outlined, size: 22, color: c.muted),
              title: map.notice!,
            ),
            const SizedBox(height: 12),
          ],
          _StartButton(active: active, busy: starting, onTap: onStart),
          const SizedBox(height: 12),
          Text(
            error ?? 'Run a closed loop. Every cell inside becomes yours.',
            key: const Key('start_hint'),
            textAlign: TextAlign.center,
            style: LrText.body(13, color: error == null ? c.muted : c.danger, height: 1.35),
          ),
        ],
      ),
    );
  }
}

/// One line of news in the sheet (60 px high, radius 18).
class _NoticeRow extends StatelessWidget {
  const _NoticeRow({super.key, required this.leading, required this.title, this.subtitle, this.onTap});
  final Widget leading;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.lr;
    final content = Row(
      children: [
        leading,
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(title, style: LrText.body(15, weight: FontWeight.w600, color: c.text)),
              if (subtitle != null) ...[
                const SizedBox(height: 2),
                Text(subtitle!, style: LrText.body(13, color: c.muted)),
              ],
            ],
          ),
        ),
        if (onTap != null) Icon(Icons.chevron_right, size: 20, color: c.muted),
      ],
    );
    const padding = EdgeInsets.symmetric(horizontal: 14, vertical: 10);
    if (onTap == null) {
      return Container(
        constraints: const BoxConstraints(minHeight: 60),
        padding: padding,
        alignment: Alignment.centerLeft,
        decoration: BoxDecoration(
          color: c.raised,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: c.line),
        ),
        child: content,
      );
    }
    return LrBox(
      onTap: onTap,
      color: c.raised,
      borderColor: c.line,
      radius: 18,
      padding: padding,
      alignment: null,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 40),
        child: content,
      ),
    );
  }
}

/// Three hexagons losing their colour.
class _FadingHexes extends StatelessWidget {
  const _FadingHexes();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 50,
      height: 24,
      child: CustomPaint(painter: _FadingHexPainter(context.lr.accent)),
    );
  }
}

class _FadingHexPainter extends CustomPainter {
  _FadingHexPainter(this.color);
  final Color color;

  static const List<List<double>> _hex = [
    [0, -8], [6.9, -4], [6.9, 4], [0, 8], [-6.9, 4], [-6.9, -4],
  ];

  void _draw(Canvas canvas, double cx, double cy, double opacity) {
    final path = Path()..moveTo(cx + _hex[0][0], cy + _hex[0][1]);
    for (var i = 1; i < _hex.length; i++) {
      path.lineTo(cx + _hex[i][0], cy + _hex[i][1]);
    }
    path.close();
    canvas.drawPath(path, Paint()..color = color.withValues(alpha: opacity));
  }

  @override
  void paint(Canvas canvas, Size size) {
    _draw(canvas, 9, 10, 1);
    _draw(canvas, 25, 14, 0.55);
    _draw(canvas, 41, 10, 0.25);
  }

  @override
  bool shouldRepaint(covariant _FadingHexPainter old) => old.color != color;
}

/// The big start button: start-line ticks, "ON YOUR MARKS / START RUN", an arrow in a disc.
class _StartButton extends StatelessWidget {
  const _StartButton({required this.active, required this.busy, required this.onTap});

  /// A run is being recorded: the button leads back to it.
  final bool active;
  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.lr;
    return LrBox(
      key: const Key('start_run_button'),
      onTap: busy ? null : onTap,
      color: c.accent,
      radius: 22,
      height: 72,
      padding: const EdgeInsets.only(left: 16, right: 14),
      alignment: null,
      semanticLabel: active ? 'Back to your run' : 'Start run',
      child: Row(
        children: [
          SizedBox(width: 6, height: 44, child: CustomPaint(painter: _TicksPainter(c.onAccent))),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  active ? 'RUN IN PROGRESS' : (busy ? 'GET SET' : 'ON YOUR MARKS'),
                  style: LrText.label(12, color: c.onAccent, height: 1),
                ),
                const SizedBox(height: 3),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    active ? 'BACK TO RUN' : 'START RUN',
                    style: LrText.display(32, color: c.onAccent, tracking: 0.02, height: 0.95),
                  ),
                ),
              ],
            ),
          ),
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(color: c.onAccent, shape: BoxShape.circle),
            child: busy
                ? Padding(
                    padding: const EdgeInsets.all(13),
                    child: CircularProgressIndicator(strokeWidth: 2.5, color: c.accent),
                  )
                : Icon(Icons.arrow_forward, size: 24, color: c.accent),
          ),
        ],
      ),
    );
  }
}

/// The start line: 6 px wide, dashes of 6 px with 6 px gaps.
class _TicksPainter extends CustomPainter {
  _TicksPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    for (var y = 0.0; y < size.height; y += 12) {
      canvas.drawRect(Rect.fromLTWH(0, y, size.width, 6), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _TicksPainter old) => old.color != color;
}
