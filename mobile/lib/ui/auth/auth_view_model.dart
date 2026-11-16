import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_exception.dart';
import '../../data/models/api_exception.dart';
import '../../data/models/models.dart';
import '../../data/providers.dart';

enum AuthStatus { unknown, signedOut, signedIn }

class AuthState {
  const AuthState({
    this.status = AuthStatus.unknown,
    this.user,
    this.busy = false,
    this.error,
  });

  final AuthStatus status;
  final UserRef? user;
  final bool busy;
  final String? error;
}

const String signInNoServerText = "Can't reach the server. Check your connection.";

/// A sentence for the user for anything that can go wrong while signing in. Never the raw exception:
/// platform and network errors are long, technical and sometimes contain addresses.
/// [apiBaseUrl] is only passed in debug builds; it is added to the "can't reach the server" text so a
/// developer sees which machine the app is talking to.
String signInErrorText(Object error, {String? apiBaseUrl, bool dev = false}) {
  if (error is AppException) return error.message;
  if (error is ApiException) {
    if (error.isNetwork) {
      return apiBaseUrl == null ? signInNoServerText : '$signInNoServerText\nServer: $apiBaseUrl';
    }
    switch (error.statusCode) {
      case 401:
        return dev
            ? 'The dev login is switched off on this server.'
            : 'The server did not accept this Google account. Please try again.';
      case 503:
        return 'Google sign-in is not set up on the server yet.';
      case 429:
        return 'Too many attempts. Wait a minute and try again.';
      default:
        return 'Sign-in did not work (server error ${error.statusCode}). Please try again.';
    }
  }
  return 'Sign-in did not work. Please try again.';
}

/// View model of the sign-in screen and the source of "who is signed in" for the router.
class AuthViewModel extends Notifier<AuthState> {
  @override
  AuthState build() {
    final repo = ref.watch(authRepositoryProvider);
    final sub = repo.changes.listen(_onSession);
    ref.onDispose(sub.cancel);
    Future<void>.microtask(_restore);
    return const AuthState();
  }

  void _onSession(AuthSession? session) {
    state = session == null
        ? const AuthState(status: AuthStatus.signedOut)
        : AuthState(status: AuthStatus.signedIn, user: session.user);
  }

  Future<void> _restore() async {
    try {
      await ref.read(authRepositoryProvider).restore();
    } catch (_) {
      state = const AuthState(status: AuthStatus.signedOut);
    }
  }

  Future<void> signInWithGoogle() async {
    state = const AuthState(status: AuthStatus.signedOut, busy: true);
    try {
      final session = await ref.read(authRepositoryProvider).signInWithGoogle();
      if (session == null) {
        // The user closed the Google dialog: not an error, say nothing.
        state = const AuthState(status: AuthStatus.signedOut);
      } else {
        state = AuthState(status: AuthStatus.signedIn, user: session.user);
      }
    } catch (e) {
      state = AuthState(
        status: AuthStatus.signedOut,
        error: signInErrorText(e, apiBaseUrl: ref.read(apiBaseUrlHintProvider)),
      );
    }
  }

  /// Development only: the server accepts `dev:<name>` when LOOPRUN_DEV_AUTH=1.
  Future<void> signInDev(String name) async {
    if (!ref.read(devAuthEnabledProvider)) return;
    state = const AuthState(status: AuthStatus.signedOut, busy: true);
    try {
      final session = await ref.read(authRepositoryProvider).signInDev(name);
      state = AuthState(status: AuthStatus.signedIn, user: session.user);
    } catch (e) {
      state = AuthState(
        status: AuthStatus.signedOut,
        error: signInErrorText(e, apiBaseUrl: ref.read(apiBaseUrlHintProvider), dev: true),
      );
    }
  }

  Future<void> signOut() async {
    await ref.read(authRepositoryProvider).signOut();
  }
}

final authViewModelProvider = NotifierProvider<AuthViewModel, AuthState>(AuthViewModel.new);

/// Whether the sign-in screen shows the development login (build flag DEV_AUTH).
final devLoginVisibleProvider = Provider<bool>((ref) => ref.watch(devAuthEnabledProvider));
