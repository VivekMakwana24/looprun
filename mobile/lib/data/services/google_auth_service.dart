import 'package:google_sign_in/google_sign_in.dart';

import '../../core/app_exception.dart';
import '../../core/config.dart';

/// Google sign-in on the device. Returns the ID token the server verifies.
abstract class GoogleAuthService {
  /// Null when the user closed the Google dialog. Throws [AppException] when Google gives no ID token.
  Future<String?> signInForIdToken();

  Future<void> signOut();
}

class PluginGoogleAuthService implements GoogleAuthService {
  @override
  Future<String?> signInForIdToken() async {
    final google = GoogleSignIn(
      scopes: const ['email'],
      serverClientId: AppConfig.googleServerClientId.isEmpty ? null : AppConfig.googleServerClientId,
    );
    final account = await google.signIn();
    if (account == null) return null;
    final auth = await account.authentication;
    final idToken = auth.idToken;
    if (idToken == null) {
      throw const AppException('Google did not return an ID token. Check the app configuration.');
    }
    return idToken;
  }

  @override
  Future<void> signOut() async {
    try {
      await GoogleSignIn().signOut();
    } catch (_) {
      // Not signed in with Google (dev login) or plugin unavailable.
    }
  }
}
