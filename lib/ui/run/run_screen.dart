import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../data/models/models.dart';
import '../../data/models/recording_snapshot.dart';
import '../../domain/recorder/gps_health.dart';
import '../../domain/recorder/run_recorder.dart';
import 'path_painter.dart';
import 'run_view_model.dart';

class RunScreen extends ConsumerWidget {
  const RunScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final run = ref.watch(runViewModelProvider);
    final controller = ref.read(runViewModelProvider.notifier);
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(alignment: Alignment.centerLeft, child: GpsHealthChip(health: run.health)),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _Metric(label: 'Time', value: formatDuration(run.elapsedMs)),
              _Metric(label: 'Distance', value: formatDistance(run.distanceM)),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: Card(
              clipBehavior: Clip.antiAlias,
              child: run.path.length < 2
                  ? Center(
                      child: Text(
                        run.isActive ? 'Your path will appear as you move' : 'Press Start to record a run',
                        style: theme.textTheme.bodyMedium,
                      ),
                    )
                  : CustomPaint(
                      painter: PathPainter(run.path, theme.colorScheme.primary),
                      size: Size.infinite,
                    ),
            ),
          ),
          if (run.error != null) ...[
            const SizedBox(height: 8),
            Text(run.error!, style: TextStyle(color: theme.colorScheme.error)),
          ],
          const SizedBox(height: 16),
          _Controls(run: run, controller: controller),
          if (!run.isActive) ...[
            const SizedBox(height: 16),
            const _RecentRuns(),
          ],
        ],
      ),
    );
  }
}

class _Controls extends StatelessWidget {
  const _Controls({required this.run, required this.controller});
  final RecordingSnapshot run;
  final RunViewModel controller;

  @override
  Widget build(BuildContext context) {
    if (run.status == RecorderStatus.stopping) {
      // The last GPS point is still being saved; a second run must not start yet.
      return const FilledButton(
        key: Key('saving_run_button'),
        onPressed: null,
        child: Text('Saving...'),
      );
    }
    if (!run.isActive) {
      return FilledButton.icon(
        key: const Key('start_run_button'),
        onPressed: controller.start,
        icon: const Icon(Icons.play_arrow),
        label: const Text('Start'),
      );
    }
    final paused = run.status == RecorderStatus.paused;
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            key: const Key('pause_run_button'),
            onPressed: paused ? controller.resume : controller.pause,
            icon: Icon(paused ? Icons.play_arrow : Icons.pause),
            label: Text(paused ? 'Resume' : 'Pause'),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: FilledButton.icon(
            key: const Key('stop_run_button'),
            onPressed: controller.stop,
            icon: const Icon(Icons.stop),
            label: const Text('Stop'),
          ),
        ),
      ],
    );
  }
}

class GpsHealthChip extends StatelessWidget {
  const GpsHealthChip({super.key, required this.health});
  final GpsHealth health;

  @override
  Widget build(BuildContext context) {
    final String label;
    final Color color;
    switch (health) {
      case GpsHealth.good:
        label = 'GPS good';
        color = healthGood;
      case GpsHealth.lost:
        label = 'GPS signal lost';
        color = healthWarn;
      case GpsHealth.searching:
        label = 'Looking for GPS';
        color = healthWarn;
      case GpsHealth.inactive:
        label = 'GPS idle';
        color = Colors.grey;
    }
    return Chip(
      key: const Key('gps_health_chip'),
      avatar: Icon(Icons.circle, size: 14, color: color),
      label: Text(label),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(value, style: Theme.of(context).textTheme.displaySmall),
        Text(label, style: Theme.of(context).textTheme.labelMedium),
      ],
    );
  }
}

class _RecentRuns extends ConsumerWidget {
  const _RecentRuns();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final runs = ref.watch(recentRunsProvider).valueOrNull ?? const <RunSummary>[];
    if (runs.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      height: 150,
      child: ListView(
        children: [
          for (final r in runs)
            ListTile(
              dense: true,
              leading: const Icon(Icons.directions_run),
              title: Text(DateTime.fromMillisecondsSinceEpoch(r.startedAt)
                  .toLocal()
                  .toString()
                  .substring(0, 16)),
              subtitle: Text(_summary(r)),
              onTap: () => context.push('/run/${r.id}'),
            ),
        ],
      ),
    );
  }

  String _summary(RunSummary r) {
    final result = r.result;
    if (result != null && !result.isProcessing) return result.status.replaceAll('_', ' ');
    return r.uploadFailed ? 'upload failed' : 'uploading';
  }
}
