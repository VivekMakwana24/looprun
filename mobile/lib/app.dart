import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/theme.dart';
import 'features/auth/auth_controller.dart';
import 'features/auth/sign_in_screen.dart';
import 'features/disclosure/disclosure_screen.dart';
import 'features/home/home_screen.dart';

class LooprunApp extends StatelessWidget {
  const LooprunApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Looprun',
      theme: buildTheme(),
      home: const AppGate(),
    );
  }
}

/// sign-in -> location disclosure -> home. The disclosure always comes before any permission prompt.
class AppGate extends ConsumerWidget {
  const AppGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider);
    switch (auth.status) {
      case AuthStatus.unknown:
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      case AuthStatus.signedOut:
        return const SignInScreen();
      case AuthStatus.signedIn:
        final accepted = ref.watch(disclosureProvider);
        return accepted ? const HomeScreen() : const DisclosureScreen();
    }
  }
}
