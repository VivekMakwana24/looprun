import 'dart:async';

import '../models/models.dart';
import '../services/api_service.dart';
import '../services/google_auth_service.dart';
import '../services/token_store.dart';

/// Source of truth for who is signed in. The token is kept in memory (for requests) and in secure storage
/// (for the next launch). [changes] publishes every sign-in and sign-out.
class AuthRepository {
  AuthRepository({
    required ApiService api,
    required TokenStore tokens,
    required GoogleAuthService google,
  })  : _api = api,
        _tokens = tokens,
        _google = google;

  final ApiService _api;
  final TokenStore _tokens;
  final GoogleAuthService _google;
  final StreamController<AuthSession?> _changes = StreamController<AuthSession?>.broadcast();

  AuthSession? _current;

  AuthSession? get current => _current;

  /// Token for the Authorization header, or null when signed out.
  String? get token => _current?.token;

  Stream<AuthSession?> get changes => _changes.stream;

  void _set(AuthSession? session) {
    _current = session;
    if (!_changes.isClosed) _changes.add(session);
  }

  /// Loads the stored session (app start). Returns it, or null when signed out.
  Future<AuthSession?> restore() async {
    final stored = await _tokens.read();
    final session = stored == null
        ? null
        : AuthSession(
            token: stored.token,
            user: UserRef(id: stored.userId, name: stored.userName),
          );
    _set(session);
    return session;
  }

  /// Null when the user closed the Google dialog. Throws on failures.
  Future<AuthSession?> signInWithGoogle() async {
    final idToken = await _google.signInForIdToken();
    if (idToken == null) return null;
    return _exchange(idToken);
  }

  /// Development only: the server accepts `dev:<name>` when LOOPRUN_DEV_AUTH=1.
  Future<AuthSession> signInDev(String name) => _exchange('dev:$name');

  Future<AuthSession> _exchange(String idToken) async {
    final session = await _api.authGoogle(idToken);
    await _tokens.write(StoredSession(
      token: session.accessToken,
      userId: session.user.id,
      userName: session.user.name,
    ));
    final result = AuthSession(token: session.accessToken, user: session.user);
    _set(result);
    return result;
  }

  Future<void> signOut() async {
    await _tokens.clear();
    await _google.signOut();
    _set(null);
  }

  /// The server refused our token (401). Signs out unless already signed out.
  Future<void> expireSession() async {
    if (_current == null) return;
    await signOut();
  }

  Future<void> dispose() => _changes.close();
}
