import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/format.dart';
import '../../core/routes.dart';
import '../../core/theme.dart';
import '../../data/models/recording_snapshot.dart';
import '../../domain/recorder/gps_health.dart';
import '../../domain/recorder/loop_gap.dart';
import '../../domain/recorder/run_recorder.dart';
import '../core/widgets.dart';
import 'loop_painter.dart';
import 'run_view_model.dart';

/// The live run: time, distance, pace, the loop so far and the controls. Recording itself lives in the
/// repository; leaving this screen does not stop it (the map's start button leads back here).
class RunScreen extends ConsumerWidget {
  const RunScreen({super.key});

  void _leave(BuildContext context) {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(homePath);
    }
  }

  Future<void> _finish(BuildContext context, WidgetRef ref) async {
    await ref.read(runViewModelProvider.notifier).stop();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.lr;
    final run = ref.watch(runViewModelProvider);
    final vm = ref.read(runViewModelProvider.notifier);
    final stopping = run.status == RecorderStatus.stopping;
    final live = run.isActive || stopping;

    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 22),
          child: live ? _Live(run: run) : _NoRun(run: run, onBack: () => _leave(context)),
        ),
      ),
      bottomNavigationBar: !live
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _Controls(
                      status: run.status,
                      onPause: vm.pause,
                      onResume: vm.resume,
                      onFinish: () => _finish(context, ref),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.lock_outline, size: 16, color: c.muted),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text('Lock your screen. Looprun keeps recording.',
                              style: LrText.body(13, color: c.muted)),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}

/// No run is being recorded (it was too short, could not start, or already finished).
class _NoRun extends StatelessWidget {
  const _NoRun({required this.run, required this.onBack});
  final RecordingSnapshot run;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final c = context.lr;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: LrIconButton(icon: Icons.close, semanticLabel: 'Close and go to the map', onTap: onBack),
        ),
        const Spacer(),
        Text('NO RUN', style: LrText.display(78, color: c.text, height: 0.9)),
        const SizedBox(height: 12),
        Text(
          run.error ?? 'Nothing is being recorded. Start a run from the map.',
          key: const Key('run_error'),
          style: LrText.body(16, weight: FontWeight.w500, color: run.error == null ? c.text2 : c.danger, height: 1.4),
        ),
        const Spacer(),
        LrBigButton(
          key: const Key('back_to_map_button'),
          label: 'BACK TO THE MAP',
          background: c.accent,
          foreground: c.onAccent,
          onTap: onBack,
        ),
      ],
    );
  }
}

class _Live extends ConsumerWidget {
  const _Live({required this.run});
  final RecordingSnapshot run;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.lr;
    final sketch = ref.watch(loopSketchProvider);
    final label = LrText.label(14, color: c.muted);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 44,
          child: Row(
            children: [
              _StatusChip(status: run.status),
              const Spacer(),
              _GpsAccuracy(health: run.health, accuracyM: run.accuracyM),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Text('TIME', style: label),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            formatDuration(run.elapsedMs),
            key: const Key('run_time'),
            style: LrText.display(124, color: c.text, tracking: -0.01, height: 0.9),
          ),
        ),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.only(top: 14),
          decoration: BoxDecoration(border: Border(top: BorderSide(color: c.line))),
          child: Row(
            children: [
              Expanded(child: _Metric(label: 'DISTANCE', value: formatKm(run.distanceM), unit: 'km')),
              Container(width: 1, height: 64, color: c.line),
              const SizedBox(width: 16),
              Expanded(
                child: _Metric(label: 'PACE', value: formatPace(run.elapsedMs, run.distanceM), unit: '/km'),
              ),
            ],
          ),
        ),
        if (run.error != null || run.notice != null) ...[
          const SizedBox(height: 12),
          Text(
            run.error ?? run.notice!,
            key: const Key('run_error'),
            style: LrText.body(13, weight: FontWeight.w500, color: run.error != null ? c.danger : c.text2, height: 1.35),
          ),
        ],
        const SizedBox(height: 14),
        Expanded(child: _LoopCard(sketch: sketch)),
      ],
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});
  final RecorderStatus status;

  @override
  Widget build(BuildContext context) {
    final c = context.lr;
    final Widget mark;
    final String text;
    final Color color;
    switch (status) {
      case RecorderStatus.paused:
        text = 'PAUSED';
        color = c.text2;
        mark = Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: c.text2, width: 2)),
        );
      case RecorderStatus.stopping:
      case RecorderStatus.finished:
        text = 'SAVING RUN';
        color = c.text2;
        mark = Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: c.text2, borderRadius: BorderRadius.circular(2)),
        );
      case RecorderStatus.recording:
      case RecorderStatus.idle:
        text = 'RECORDING';
        color = c.accentText;
        mark = Container(width: 10, height: 10, decoration: BoxDecoration(color: c.accent, shape: BoxShape.circle));
    }
    return Row(
      key: const Key('run_status'),
      mainAxisSize: MainAxisSize.min,
      children: [mark, const SizedBox(width: 8), Text(text, style: LrText.label(15, color: color))],
    );
  }
}

class _GpsAccuracy extends StatelessWidget {
  const _GpsAccuracy({required this.health, required this.accuracyM});
  final GpsHealth health;
  final double? accuracyM;

  @override
  Widget build(BuildContext context) {
    final c = context.lr;
    final String text;
    var warn = false;
    switch (health) {
      case GpsHealth.lost:
        text = 'GPS lost';
        warn = true;
      case GpsHealth.searching:
        text = 'Looking for GPS';
        warn = true;
      case GpsHealth.good:
      case GpsHealth.inactive:
        final acc = accuracyM;
        text = acc == null ? 'GPS' : 'GPS ±${acc.round()} m';
    }
    final color = warn ? c.danger : c.muted;
    return Row(
      key: const Key('gps_health_chip'),
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.signal_cellular_alt, size: 18, color: color),
        const SizedBox(width: 8),
        Text(text, style: LrText.body(14, weight: FontWeight.w500, color: color)),
      ],
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value, required this.unit});
  final String label;
  final String value;
  final String unit;

  @override
  Widget build(BuildContext context) {
    final c = context.lr;
    return Semantics(
      label: '$label $value $unit',
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: LrText.label(14, color: c.muted)),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(value, style: LrText.display(52, color: c.text, height: 0.95)),
                const SizedBox(width: 6),
                Text(unit, style: LrText.body(16, weight: FontWeight.w500, color: c.text2)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LoopCard extends StatelessWidget {
  const _LoopCard({required this.sketch});
  final LoopSketch sketch;

  @override
  Widget build(BuildContext context) {
    final c = context.lr;
    final p = sketch.progress;
    final gap = p.gapM;
    final String big;
    final String small;
    final String rule;
    if (p.closed) {
      big = 'Loop';
      small = 'closed';
      rule = 'Keep running or finish. The server counts the cells when you finish.';
    } else if (gap == null) {
      big = 'Go';
      small = 'run out, then come back round';
      rule = 'It closes when you cross your path or come within 80 m of it.';
    } else {
      big = formatDistance(gap);
      small = 'to close the loop';
      rule = 'It closes when you cross your path or come within 80 m of it.';
    }
    final semantics = p.closed
        ? 'Your route so far. The loop is closed.'
        : gap == null
            ? 'Your route so far.'
            : 'Your route so far, ${gap.round()} metres short of closing the loop';
    return LrCard(
      radius: 26,
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text('YOUR LOOP SO FAR', style: LrText.label(14, color: c.muted)),
              const Spacer(),
              Flexible(
                child: Text('Start is the ringed dot',
                    overflow: TextOverflow.ellipsis, style: LrText.body(13, color: c.muted)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Expanded(
            child: Semantics(
              image: true,
              label: semantics,
              child: CustomPaint(
                key: const Key('loop_picture'),
                size: Size.infinite,
                painter: LoopPainter(
                  sketch: sketch,
                  colors: LoopPaintColors(track: c.accent, text: c.text, surface: c.surface, grid: c.line),
                  labelStyle: LrText.label(12, weight: FontWeight.w700, tracking: 0),
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            key: const Key('loop_gap'),
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(big, style: LrText.display(46, color: c.accentText, height: 0.9)),
              const SizedBox(width: 8),
              Flexible(child: Text(small, style: LrText.body(15, weight: FontWeight.w500, color: c.text))),
            ],
          ),
          const SizedBox(height: 6),
          Text(rule, style: LrText.body(13, color: c.muted, height: 1.35)),
        ],
      ),
    );
  }
}

class _Controls extends StatelessWidget {
  const _Controls({required this.status, required this.onPause, required this.onResume, required this.onFinish});
  final RecorderStatus status;
  final VoidCallback onPause;
  final VoidCallback onResume;
  final VoidCallback onFinish;

  @override
  Widget build(BuildContext context) {
    final c = context.lr;
    final stopMark = Container(
      width: 16,
      height: 16,
      decoration: BoxDecoration(color: c.onPaper, borderRadius: BorderRadius.circular(4)),
    );
    if (status == RecorderStatus.stopping || status == RecorderStatus.finished) {
      // The last GPS point is still being saved; a second run must not start yet.
      return LrBigButton(
        key: const Key('saving_run_button'),
        label: 'SAVING…',
        background: c.raised,
        foreground: c.text2,
        borderColor: c.line,
      );
    }
    if (status == RecorderStatus.paused) {
      return Row(
        children: [
          Expanded(
            child: LrBigButton(
              key: const Key('resume_run_button'),
              label: 'RESUME',
              background: c.accent,
              foreground: c.onAccent,
              leading: Icon(Icons.play_arrow, size: 24, color: c.onAccent),
              onTap: onResume,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: LrBigButton(
              key: const Key('stop_run_button'),
              label: 'FINISH',
              background: c.paper,
              foreground: c.onPaper,
              leading: stopMark,
              onTap: onFinish,
            ),
          ),
        ],
      );
    }
    return Row(
      children: [
        LrBox(
          key: const Key('pause_run_button'),
          onTap: onPause,
          semanticLabel: 'Pause run',
          color: c.raised,
          borderColor: c.line,
          radius: 24,
          width: 68,
          height: 68,
          child: Icon(Icons.pause, size: 28, color: c.text),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: LrBigButton(
            key: const Key('stop_run_button'),
            label: 'FINISH RUN',
            background: c.paper,
            foreground: c.onPaper,
            leading: stopMark,
            onTap: onFinish,
          ),
        ),
      ],
    );
  }
}
