import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../../core/config.dart';
import '../../core/providers.dart';
import '../../data/services/token_store.dart';
import '../../data/models/api_exception.dart';
import '../../data/models/models.dart';

enum AuthStatus { unknown, signedOut, signedIn }

class AuthState {
  const AuthState({
    this.status = AuthStatus.unknown,
    this.token,
    this.user,
    this.busy = false,
    this.error,
  });

  final AuthStatus status;
  final String? token;
  final UserRef? user;
  final bool busy;
  final String? error;
}

class AuthController extends Notifier<AuthState> {
  @override
  AuthState build() {
    Future.microtask(_restore);
    return const AuthState();
  }

  Future<void> _restore() async {
    final stored = await ref.read(tokenStoreProvider).read();
    if (stored == null) {
      state = const AuthState(status: AuthStatus.signedOut);
    } else {
      state = AuthState(
        status: AuthStatus.signedIn,
        token: stored.token,
        user: UserRef(id: stored.userId, name: stored.userName),
      );
    }
  }

  Future<void> signInWithGoogle() async {
    state = const AuthState(status: AuthStatus.signedOut, busy: true);
    try {
      final google = GoogleSignIn(
        scopes: const ['email'],
        serverClientId:
            AppConfig.googleServerClientId.isEmpty ? null : AppConfig.googleServerClientId,
      );
      final account = await google.signIn();
      if (account == null) {
        state = const AuthState(status: AuthStatus.signedOut);
        return;
      }
      final auth = await account.authentication;
      final idToken = auth.idToken;
      if (idToken == null) {
        state = const AuthState(
          status: AuthStatus.signedOut,
          error: 'Google did not return an ID token. Check the app configuration.',
        );
        return;
      }
      await _exchange(idToken);
    } on ApiException catch (e) {
      state = AuthState(status: AuthStatus.signedOut, error: 'Sign-in failed: ${e.message}');
    } catch (e) {
      state = AuthState(status: AuthStatus.signedOut, error: 'Sign-in failed: $e');
    }
  }

  /// Development only: the server accepts "dev:<name>" when LOOPRUN_DEV_AUTH=1.
  Future<void> signInDev(String name) async {
    if (!ref.read(devAuthEnabledProvider)) return;
    state = const AuthState(status: AuthStatus.signedOut, busy: true);
    try {
      await _exchange('dev:$name');
    } on ApiException catch (e) {
      state = AuthState(status: AuthStatus.signedOut, error: 'Dev sign-in failed: ${e.message}');
    } catch (e) {
      state = AuthState(status: AuthStatus.signedOut, error: 'Dev sign-in failed: $e');
    }
  }

  Future<void> _exchange(String idToken) async {
    final session = await ref.read(apiClientProvider).authGoogle(idToken);
    await ref.read(tokenStoreProvider).write(StoredSession(
          token: session.accessToken,
          userId: session.user.id,
          userName: session.user.name,
        ));
    state = AuthState(
      status: AuthStatus.signedIn,
      token: session.accessToken,
      user: session.user,
    );
  }

  Future<void> signOut() async {
    await ref.read(tokenStoreProvider).clear();
    try {
      await GoogleSignIn().signOut();
    } catch (_) {
      // Not signed in with Google (dev login) or plugin unavailable.
    }
    state = const AuthState(status: AuthStatus.signedOut);
  }
}

final authProvider = NotifierProvider<AuthController, AuthState>(AuthController.new);
