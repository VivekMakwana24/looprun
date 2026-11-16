import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/theme.dart';
import 'router.dart';
import 'ui/core/theme_view_model.dart';

class LooprunApp extends ConsumerWidget {
  const LooprunApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeId = ref.watch(themeViewModelProvider);
    return MaterialApp.router(
      title: 'Looprun',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(themeId),
      routerConfig: ref.watch(routerProvider),
    );
  }
}

/// Shown instead of the app when a release build was made without its settings (review F19): better a
/// clear message than a store build that talks to the emulator address or shows placeholder legal text.
class ConfigErrorApp extends StatelessWidget {
  const ConfigErrorApp({super.key, required this.problems});
  final List<String> problems;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Looprun',
      theme: buildTheme(),
      home: Builder(
        builder: (context) {
          final c = context.lr;
          return Scaffold(
            body: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('LOOPRUN', style: LrText.display(48, color: c.text)),
                    const SizedBox(height: 16),
                    Text(
                      'This build is not set up correctly and cannot be used.',
                      style: LrText.body(18, weight: FontWeight.w600, color: c.text),
                    ),
                    const SizedBox(height: 12),
                    for (final p in problems)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Text(p, style: LrText.body(14, color: c.text2, height: 1.4)),
                      ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
