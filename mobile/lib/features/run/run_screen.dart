import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/providers.dart';
import '../../core/theme.dart';
import '../../data/api/models.dart';
import '../../data/db/app_database.dart';
import '../../recorder/gps_health.dart';
import '../../recorder/run_recorder.dart';
import '../run_result/run_result_screen.dart';
import 'path_painter.dart';
import 'run_controller.dart';

final recentRunsProvider = StreamProvider.autoDispose<List<RunRow>>(
  (ref) => ref.watch(databaseProvider).watchRecentRuns(limit: 10),
);

class RunScreen extends ConsumerWidget {
  const RunScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen<RunUiState>(runControllerProvider, (prev, next) {
      final id = next.finishedRunId;
      if (id != null && prev?.finishedRunId != id) {
        ref.read(runControllerProvider.notifier).acknowledge();
        Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => RunResultScreen(runId: id)),
        );
      }
    });

    final run = ref.watch(runControllerProvider);
    final controller = ref.read(runControllerProvider.notifier);
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
  final RunUiState run;
  final RunController controller;

  @override
  Widget build(BuildContext context) {
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
    final runs = ref.watch(recentRunsProvider).valueOrNull ?? const <RunRow>[];
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
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => RunResultScreen(runId: r.id)),
              ),
            ),
        ],
      ),
    );
  }

  String _summary(RunRow r) {
    final raw = r.resultJson;
    if (raw != null) {
      try {
        final s = RunStatus.fromJson((jsonDecode(raw) as Map).cast<String, dynamic>());
        if (!s.isProcessing) return s.status.replaceAll('_', ' ');
      } catch (_) {}
    }
    return r.upload == 'failed' ? 'upload failed' : 'uploading';
  }
}
