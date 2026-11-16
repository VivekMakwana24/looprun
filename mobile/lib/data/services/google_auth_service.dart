import 'package:flutter/services.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../../core/app_exception.dart';
import '../../core/config.dart';

/// Google sign-in on the device. Returns the ID token the server verifies.
abstract class GoogleAuthService {
  /// Null when the user closed the Google dialog. Throws [AppException] (with a text that can be shown
  /// as it is) when Google gives no ID token.
  Future<String?> signInForIdToken();

  Future<void> signOut();
}

const String googleNotSetUpMessage = 'Google sign-in is not set up for this build yet';
const String googleNetworkMessage = "Can't reach Google. Check your connection.";
const String googleFailedMessage = 'Google sign-in did not work. Please try again.';

/// Turns the plugin's error into a sentence for the user, or null when the user simply cancelled.
/// Never returns the raw platform text. Android status codes (com.google.android.gms.common.api):
/// 10 = DEVELOPER_ERROR (package name / SHA-1 / client id do not match the Google Cloud project),
/// 12501 = SIGN_IN_CANCELLED, 12502 = SIGN_IN_CURRENTLY_IN_PROGRESS, 7 = NETWORK_ERROR.
String? googleSignInErrorMessage(String code, String? message) {
  final text = '$code ${message ?? ''}';
  bool has(int status) =>
      RegExp('(ApiException:\\s*|^|[^0-9])$status([^0-9]|\$)').hasMatch(text);
  if (code == 'sign_in_canceled' || has(12501) || has(12502)) return null;
  if (code == 'network_error' || has(7)) return googleNetworkMessage;
  if (has(10)) return googleNotSetUpMessage;
  return googleFailedMessage;
}

class PluginGoogleAuthService implements GoogleAuthService {
  @override
  Future<String?> signInForIdToken() async {
    final google = GoogleSignIn(
      scopes: const ['email'],
      serverClientId: AppConfig.googleServerClientId.isEmpty ? null : AppConfig.googleServerClientId,
    );
    String? idToken;
    try {
      final account = await google.signIn();
      if (account == null) return null;
      idToken = (await account.authentication).idToken;
    } on PlatformException catch (e) {
      final text = googleSignInErrorMessage(e.code, e.message);
      if (text == null) return null;
      throw AppException(text);
    } catch (_) {
      throw const AppException(googleFailedMessage);
    }
    if (idToken == null) {
      // No ID token means the web client id is missing or wrong for this build.
      throw const AppException(googleNotSetUpMessage);
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
