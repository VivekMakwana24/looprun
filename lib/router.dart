import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'ui/auth/auth_view_model.dart';
import 'ui/auth/sign_in_screen.dart';
import 'ui/disclosure/disclosure_screen.dart';
import 'ui/disclosure/disclosure_view_model.dart';
import 'ui/home/home_screen.dart';
import 'ui/run_result/run_result_screen.dart';

const String splashPath = '/splash';
const String signInPath = '/sign-in';
const String disclosurePath = '/disclosure';
const String homePath = '/home';

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

  final router = GoRouter(
    initialLocation: homePath,
    refreshListenable: refresh,
    redirect: (context, state) => appRedirect(
      status: ref.read(authViewModelProvider).status,
      disclosureAccepted: ref.read(disclosureViewModelProvider),
      location: state.matchedLocation,
    ),
    routes: [
      GoRoute(
        path: splashPath,
        builder: (context, state) =>
            const Scaffold(body: Center(child: CircularProgressIndicator())),
      ),
      GoRoute(path: signInPath, builder: (context, state) => const SignInScreen()),
      GoRoute(path: disclosurePath, builder: (context, state) => const DisclosureScreen()),
      GoRoute(path: homePath, builder: (context, state) => const HomeScreen()),
      GoRoute(
        path: '/run/:id',
        builder: (context, state) => RunResultScreen(runId: state.pathParameters['id']!),
      ),
    ],
  );
  ref.onDispose(() {
    router.dispose();
    refresh.dispose();
  });
  return router;
});
