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
        state = const AuthState(status: AuthStatus.signedOut);
      } else {
        state = AuthState(status: AuthStatus.signedIn, user: session.user);
      }
    } on ApiException catch (e) {
      state = AuthState(status: AuthStatus.signedOut, error: 'Sign-in failed: ${e.message}');
    } on AppException catch (e) {
      state = AuthState(status: AuthStatus.signedOut, error: e.message);
    } catch (e) {
      state = AuthState(status: AuthStatus.signedOut, error: 'Sign-in failed: $e');
    }
  }

  /// Development only: the server accepts `dev:<name>` when LOOPRUN_DEV_AUTH=1.
  Future<void> signInDev(String name) async {
    if (!ref.read(devAuthEnabledProvider)) return;
    state = const AuthState(status: AuthStatus.signedOut, busy: true);
    try {
      final session = await ref.read(authRepositoryProvider).signInDev(name);
      state = AuthState(status: AuthStatus.signedIn, user: session.user);
    } on ApiException catch (e) {
      state = AuthState(status: AuthStatus.signedOut, error: 'Dev sign-in failed: ${e.message}');
    } catch (e) {
      state = AuthState(status: AuthStatus.signedOut, error: 'Dev sign-in failed: $e');
    }
  }

  Future<void> signOut() async {
    await ref.read(authRepositoryProvider).signOut();
  }
}

final authViewModelProvider = NotifierProvider<AuthViewModel, AuthState>(AuthViewModel.new);

/// Whether the sign-in screen shows the development login (build flag DEV_AUTH).
final devLoginVisibleProvider = Provider<bool>((ref) => ref.watch(devAuthEnabledProvider));
