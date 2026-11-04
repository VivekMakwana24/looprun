import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/providers.dart';
import '../../data/models/models.dart';
import '../../data/db/app_database.dart';
import '../../data/upload/upload_queue.dart';

final runRowProvider = StreamProvider.autoDispose.family<RunRow?, String>(
  (ref, id) => ref.watch(databaseProvider).watchRun(id),
);

class RunResultScreen extends ConsumerWidget {
  const RunResultScreen({super.key, required this.runId});
  final String runId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final row = ref.watch(runRowProvider(runId)).valueOrNull;
    return Scaffold(
      appBar: AppBar(title: const Text('Run result')),
      body: row == null
          ? const Center(child: CircularProgressIndicator())
          : _Body(row: row),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.row});
  final RunRow row;

  RunStatus? _result() {
    final raw = row.resultJson;
    if (raw == null) return null;
    try {
      return RunStatus.fromJson((jsonDecode(raw) as Map).cast<String, dynamic>());
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final result = _result();
    final theme = Theme.of(context);

    if (row.upload == 'failed') {
      return _Message(
        icon: Icons.error_outline,
        title: 'Upload did not work',
        text:
            '${row.lastError ?? 'Unknown error'}\n\nYour run is saved on this phone. You can try again.',
        action: FilledButton(
          onPressed: () async {
            await ref.read(uploadQueueProvider).requeue(row.id);
            await ref.read(uploadQueueProvider).tick();
          },
          child: const Text('Try again'),
        ),
      );
    }

    if (result == null || result.isProcessing || row.upload == UploadStage.queued.name) {
      final retrying = row.attempts > 0;
      return _Message(
        icon: Icons.cloud_upload_outlined,
        title: result == null ? 'Uploading your run' : 'Working out your loops',
        text: retrying
            ? 'No connection yet. Your run is saved and we will keep trying (attempt ${row.attempts + 1}).'
            : 'This usually takes a few seconds. You can leave this screen; the result will be here later.',
        showProgress: true,
      );
    }

    final distance = result.distanceM == null ? '-' : formatDistance(result.distanceM!);
    final moving = result.movingSeconds == null ? '-' : formatDuration(result.movingSeconds! * 1000);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _StatusBanner(status: result.status),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _Stat(label: 'Distance', value: distance),
            _Stat(label: 'Moving time', value: moving),
            _Stat(label: 'Loops', value: '${result.loops.length}'),
          ],
        ),
        const SizedBox(height: 16),
        if (result.status == RunStatus.accepted) ...[
          Card(
            child: ListTile(
              leading: const Icon(Icons.hexagon_outlined),
              title: Text('${result.cellsClaimed} cells gained'),
              subtitle: Text('${result.cellsTakenFromOthers} of them taken from other runners'),
            ),
          ),
        ],
        for (var i = 0; i < result.loops.length; i++)
          ListTile(
            dense: true,
            leading: const Icon(Icons.loop),
            title: Text('Loop ${i + 1}: ${result.loops[i].cells} cells'),
            subtitle: Text('${result.loops[i].areaKm2.toStringAsFixed(3)} km2'),
          ),
        if (result.flags.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text('Things we noticed', style: theme.textTheme.titleMedium),
          for (final f in result.flags)
            ListTile(
              dense: true,
              leading: Icon(f.isHard ? Icons.warning_amber : Icons.info_outline),
              title: Text(describeFlag(f)),
            ),
        ],
      ],
    );
  }
}

class _StatusBanner extends StatelessWidget {
  const _StatusBanner({required this.status});
  final String status;

  @override
  Widget build(BuildContext context) {
    final String title;
    final String text;
    final IconData icon;
    switch (status) {
      case RunStatus.accepted:
        title = 'Run counted';
        text = 'Nice work. Your loops have been added to the map.';
        icon = Icons.check_circle_outline;
      case RunStatus.pendingReview:
        title = 'Pending review';
        text =
            'Something in the GPS data looked unusual, so we are holding this run for a check before giving out cells. '
            'Your run is saved and nothing is lost. If it passes, the cells will be added.';
        icon = Icons.hourglass_top;
      case RunStatus.rejected:
        title = 'Run not counted';
        text = 'This run could not be counted. See the notes below.';
        icon = Icons.block;
      default:
        title = 'Run received';
        text = '';
        icon = Icons.info_outline;
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 32),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.titleMedium),
                  if (text.isNotEmpty) ...[const SizedBox(height: 4), Text(text)],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(value, style: Theme.of(context).textTheme.headlineSmall),
        Text(label, style: Theme.of(context).textTheme.labelMedium),
      ],
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({
    required this.icon,
    required this.title,
    required this.text,
    this.action,
    this.showProgress = false,
  });
  final IconData icon;
  final String title;
  final String text;
  final Widget? action;
  final bool showProgress;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48),
            const SizedBox(height: 16),
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(text, textAlign: TextAlign.center),
            if (showProgress) ...[
              const SizedBox(height: 16),
              const CircularProgressIndicator(),
            ],
            if (action != null) ...[const SizedBox(height: 16), action!],
          ],
        ),
      ),
    );
  }
}
