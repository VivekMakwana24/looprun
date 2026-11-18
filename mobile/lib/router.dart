import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/routes.dart';
import 'core/theme.dart';
import 'ui/auth/auth_view_model.dart';
import 'data/models/social_models.dart';
import 'ui/auth/sign_in_screen.dart';
import 'ui/board/board_screen.dart';
import 'ui/disclosure/disclosure_screen.dart';
import 'ui/disclosure/disclosure_view_model.dart';
import 'ui/home/home_screen.dart';
import 'ui/feed/run_detail_screen.dart';
import 'ui/history/history_screen.dart';
import 'ui/inbox/inbox_screen.dart';
import 'ui/map/map_screen.dart';
import 'ui/people/people_view_models.dart' show PeopleKind;
import 'ui/people/public_profile_screen.dart';
import 'ui/people/user_list_screen.dart';
import 'ui/people/user_search_screen.dart';
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
      // The three lanes keep their state (review follow-up 3): the map is not rebuilt on a lane switch, so
      // the camera stays and no new GPS read happens.
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => HomeShell(
          lane: shell.currentIndex,
          onSelectLane: (i) => shell.goBranch(i, initialLocation: i == shell.currentIndex),
          child: shell,
        ),
        branches: [
          StatefulShellBranch(routes: [
            GoRoute(
              path: homePath,
              builder: (context, state) => const MapScreen(),
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
                GoRoute(
                  path: 'inbox',
                  parentNavigatorKey: rootKey,
                  builder: (context, state) => const InboxScreen(),
                ),
              ],
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: boardPath,
              builder: (context, state) => const BoardScreen(),
              routes: [
                GoRoute(
                  path: 'search',
                  parentNavigatorKey: rootKey,
                  builder: (context, state) => const UserSearchScreen(),
                ),
                GoRoute(
                  path: 'rivals',
                  parentNavigatorKey: rootKey,
                  builder: (context, state) => const UserListScreen(kind: PeopleKind.rivals),
                ),
                GoRoute(
                  path: 'run/:id',
                  parentNavigatorKey: rootKey,
                  builder: (context, state) => RunDetailScreen(
                    runId: state.pathParameters['id']!,
                    card: state.extra is RunCard ? state.extra! as RunCard : null,
                  ),
                ),
                GoRoute(
                  path: 'user/:id',
                  parentNavigatorKey: rootKey,
                  builder: (context, state) => PublicProfileScreen(userId: state.pathParameters['id']!),
                ),
              ],
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: profilePath,
              builder: (context, state) => const ProfileScreen(),
              routes: [
                GoRoute(
                  path: 'history',
                  parentNavigatorKey: rootKey,
                  builder: (context, state) => const HistoryScreen(),
                ),
                GoRoute(
                  path: 'followers',
                  parentNavigatorKey: rootKey,
                  builder: (context, state) => const UserListScreen(kind: PeopleKind.followers),
                ),
                GoRoute(
                  path: 'following',
                  parentNavigatorKey: rootKey,
                  builder: (context, state) => const UserListScreen(kind: PeopleKind.following),
                ),
                GoRoute(
                  path: 'blocked',
                  parentNavigatorKey: rootKey,
                  builder: (context, state) => const UserListScreen(kind: PeopleKind.blocked),
                ),
              ],
            ),
          ]),
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
