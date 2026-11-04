import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../map/map_screen.dart';
import '../profile/profile_screen.dart';
import '../run/recovery.dart';
import '../run/run_controller.dart';
import '../run/run_screen.dart';
import '../run_result/run_result_screen.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  int _index = 1;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkRecovery());
  }

  /// Crash recovery: a run that was still "recording" when the app started was interrupted.
  Future<void> _checkRecovery() async {
    // A run recorded by this very process is not an interrupted one.
    if (ref.read(runControllerProvider).isActive) return;
    final db = ref.read(databaseProvider);
    // A service left over from a previous process must not keep showing "Recording".
    try {
      await ref.read(runServiceProvider).stopIfRunning();
    } catch (_) {}
    final run = await db.unfinishedRun();
    if (run == null || !mounted) return;
    if (ref.read(runControllerProvider).isActive) return;
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
      final queued = await finishRecoveredRun(db, run);
      if (!mounted) return;
      if (queued) {
        ref.read(uploadQueueProvider).tick();
        Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => RunResultScreen(runId: run.id)),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('That run was too short to keep.')),
        );
      }
    } else {
      await db.discardRun(run.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(uploadTickerProvider);
    const pages = <Widget>[MapScreen(), RunScreen(), ProfileScreen()];
    return Scaffold(
      body: SafeArea(child: pages[_index]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.map_outlined), label: 'Map'),
          NavigationDestination(icon: Icon(Icons.directions_run), label: 'Run'),
          NavigationDestination(icon: Icon(Icons.person_outline), label: 'Profile'),
        ],
      ),
    );
  }
}
