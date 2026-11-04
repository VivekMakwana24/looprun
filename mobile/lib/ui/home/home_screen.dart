import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../map/map_screen.dart';
import '../profile/profile_screen.dart';
import '../run/run_screen.dart';
import '../run/run_view_model.dart';
import 'home_view_model.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
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
        context.push('/run/${run.id}');
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

    // Open the result when a run finished, whichever tab is showing (also after the notification's Stop).
    ref.listen<String?>(runViewModelProvider.select((s) => s.finishedRunId), (previous, next) {
      if (next != null && next != previous) {
        ref.read(runViewModelProvider.notifier).acknowledge();
        context.push('/run/$next');
      }
    });

    final index = ref.watch(homeViewModelProvider);
    const pages = <Widget>[MapScreen(), RunScreen(), ProfileScreen()];
    return Scaffold(
      body: SafeArea(child: pages[index]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: ref.read(homeViewModelProvider.notifier).select,
        destinations: const [
          NavigationDestination(icon: Icon(Icons.map_outlined), label: 'Map'),
          NavigationDestination(icon: Icon(Icons.directions_run), label: 'Run'),
          NavigationDestination(icon: Icon(Icons.person_outline), label: 'Profile'),
        ],
      ),
    );
  }
}
