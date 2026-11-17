import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/routes.dart';
import 'core/theme.dart';
import 'ui/auth/auth_view_model.dart';
import 'ui/auth/sign_in_screen.dart';
import 'ui/disclosure/disclosure_screen.dart';
import 'ui/disclosure/disclosure_view_model.dart';
import 'ui/home/home_screen.dart';
import 'ui/leaderboard/leaderboard_screen.dart';
import 'ui/map/map_screen.dart';
import 'ui/profile/profile_screen.dart';
import 'ui/run/run_screen.dart';
import 'ui/run_result/run_result_screen.dart';

export 'core/routes.dart';

/// The one routing rule: signed out -> sign-in, signed in without the disclosure accepted -> disclosure,
/// otherwise the app. The disclosure always comes before any permission prompt. Returns null to stay.
String? appRedirect({
  required AuthStatus status,
  required bool disclosureAccepted,
  required String location,
}) {
  if (status == AuthStatus.unknown) {
    return location == splashPath ? null : splashPath;
  }
  if (status == AuthStatus.signedOut) {
    return location == signInPath ? null : signInPath;
  }
  if (!disclosureAccepted) {
    return location == disclosurePath ? null : disclosurePath;
  }
  if (location == signInPath || location == disclosurePath || location == splashPath) {
    return homePath;
  }
  return null;
}

/// Lane index of a location (0 map, 1 board, 2 you).
int laneOf(String location) {
  if (location.startsWith(boardPath)) return 1;
  if (location.startsWith(profilePath)) return 2;
  return 0;
}

const List<String> lanePaths = [homePath, boardPath, profilePath];

Page<void> _plain(GoRouterState state, Widget child) => NoTransitionPage<void>(key: state.pageKey, child: child);

final routerProvider = Provider<GoRouter>((ref) {
  final refresh = ValueNotifier<int>(0);
  ref.listen<AuthState>(authViewModelProvider, (previous, next) => refresh.value++);
  ref.listen<bool>(disclosureViewModelProvider, (previous, next) => refresh.value++);
  final rootKey = GlobalKey<NavigatorState>(debugLabel: 'root');

  final router = GoRouter(
    navigatorKey: rootKey,
    initialLocation: homePath,
    refreshListenable: refresh,
    redirect: (context, state) => appRedirect(
      status: ref.read(authViewModelProvider).status,
      disclosureAccepted: ref.read(disclosureViewModelProvider),
      location: state.matchedLocation,
    ),
    routes: [
      GoRoute(path: splashPath, builder: (context, state) => const _Splash()),
      GoRoute(path: signInPath, builder: (context, state) => const SignInScreen()),
      GoRoute(path: disclosurePath, builder: (context, state) => const DisclosureScreen()),
      ShellRoute(
        builder: (context, state, child) => HomeShell(lane: laneOf(state.matchedLocation), child: child),
        routes: [
          GoRoute(
            path: homePath,
            pageBuilder: (context, state) => _plain(state, const MapScreen()),
            routes: [
              GoRoute(
                path: 'record',
                parentNavigatorKey: rootKey,
                builder: (context, state) => const RunScreen(),
              ),
              GoRoute(
                path: 'run/:id',
                parentNavigatorKey: rootKey,
                builder: (context, state) => RunResultScreen(runId: state.pathParameters['id']!),
              ),
            ],
          ),
          GoRoute(path: boardPath, pageBuilder: (context, state) => _plain(state, const LeaderboardScreen())),
          GoRoute(path: profilePath, pageBuilder: (context, state) => _plain(state, const ProfileScreen())),
        ],
      ),
    ],
  );
  ref.onDispose(() {
    router.dispose();
    refresh.dispose();
  });
  return router;
});

class _Splash extends StatelessWidget {
  const _Splash();

  @override
  Widget build(BuildContext context) {
    final c = context.lr;
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('LOOPRUN', style: LrText.display(48, color: c.text, height: 1)),
            const SizedBox(height: 20),
            SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 3, color: c.accent)),
          ],
        ),
      ),
    );
  }
}
