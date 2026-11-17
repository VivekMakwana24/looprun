import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/routes.dart';
import '../../core/theme.dart';
import '../core/widgets.dart';
import '../run/run_view_model.dart';
import 'home_view_model.dart';

/// The frame around the three lanes (map, board, you): the lane bar, crash recovery, the upload
/// ticker, and opening the result when a run finished (also after the notification's Stop button).
class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key, required this.lane, required this.child});

  /// 0 map, 1 board, 2 you.
  final int lane;
  final Widget child;

  static const List<String> _paths = [homePath, boardPath, profilePath];

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkRecovery());
  }

  /// Crash recovery: a run that was still "recording" when the app started was interrupted.
  Future<void> _checkRecovery() async {
    final vm = ref.read(homeViewModelProvider.notifier);
    final run = await vm.findUnfinishedRun();
    if (run == null || !mounted) return;
    final finish = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Unfinished run found'),
        content: const Text(
            'Looprun stopped while you were recording. Finish this run and upload what was recorded, or discard it?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Discard')),
          FilledButton(
            key: const Key('recover_finish_button'),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Finish and upload'),
          ),
        ],
      ),
    );
    if (finish == true) {
      final queued = await vm.finishRecovered(run.id);
      if (!mounted) return;
      if (queued) {
        context.go(runResultPath(run.id));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('That run was too short to keep.')),
        );
      }
    } else {
      await vm.discard(run.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(uploadSyncProvider);
    ref.listen<String?>(runViewModelProvider.select((s) => s.finishedRunId), (previous, next) {
      if (next != null && next != previous) {
        ref.read(runViewModelProvider.notifier).acknowledge();
        // Replaces the live run screen (if open) with the result; back leads to the map.
        context.go(runResultPath(next));
      }
    });
    return Scaffold(
      backgroundColor: context.lr.bg,
      body: widget.child,
      bottomNavigationBar: LaneNav(
        current: widget.lane,
        onSelect: (i) {
          if (i != widget.lane) context.go(HomeShell._paths[i]);
        },
      ),
    );
  }
}
