import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/theme.dart';
import 'router.dart';

class LooprunApp extends ConsumerWidget {
  const LooprunApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      title: 'Looprun',
      theme: buildTheme(),
      routerConfig: ref.watch(routerProvider),
    );
  }
}
