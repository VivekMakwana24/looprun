import 'package:flutter/foundation.dart';

/// Build-time configuration, supplied with --dart-define.
class AppConfig {
  static const String apiBaseUrl =
      String.fromEnvironment('API_BASE_URL', defaultValue: 'http://10.0.2.2:8000');

  /// The dev login (`id_token = "dev:<name>"`). On by default in debug builds, off in profile builds unless
  /// DEV_AUTH=true is passed, and never available in a release build whatever is passed.
  static const bool devAuth =
      !kReleaseMode && bool.fromEnvironment('DEV_AUTH', defaultValue: kDebugMode);

  /// OAuth client of type "Web application": Google returns an ID token with this audience, which the
  /// server verifies. The Android-type client (package app.looprun.looprun + signing SHA-1) lives in the
  /// same Google Cloud project and needs no value here. Override with --dart-define for another project.
  static const String googleServerClientId = String.fromEnvironment(
    'GOOGLE_SERVER_CLIENT_ID',
    defaultValue: '623419287179-qsuu1f445he87kb6bomk1lp40fnmadk9.apps.googleusercontent.com',
  );

  /// Shown in the location disclosure. Set both for release builds.
  static const String mapTileProvider =
      String.fromEnvironment('MAP_TILE_PROVIDER', defaultValue: tileProviderPlaceholder);
  static const String privacyPolicyUrl =
      String.fromEnvironment('PRIVACY_POLICY_URL', defaultValue: privacyPolicyPlaceholder);

  /// MapLibre style JSON URL. Empty (the default) means the built-in style: a plain background in the
  /// theme's map colour, no tiles and no request to any map server.
  static const String mapStyleUrl = String.fromEnvironment('MAP_STYLE_URL', defaultValue: '');

  static const String tileProviderPlaceholder = '[MAP_TILE_PROVIDER]';
  static const String privacyPolicyPlaceholder = '[PRIVACY_POLICY_URL]';
}

/// What is wrong with a configuration for a release build; empty when it may ship (review F19).
/// A release with any of these would show placeholder text in the location disclosure, talk to the
/// emulator address, or send the session token over plain HTTP.
List<String> releaseConfigProblems({
  required String apiBaseUrl,
  required String mapTileProvider,
  required String privacyPolicyUrl,
  required String mapStyleUrl,
  required String googleServerClientId,
}) {
  final problems = <String>[];
  if (!apiBaseUrl.startsWith('https://')) {
    problems.add('API_BASE_URL must be an https:// address');
  }
  if (mapTileProvider.isEmpty || mapTileProvider == AppConfig.tileProviderPlaceholder) {
    problems.add('MAP_TILE_PROVIDER is not set');
  }
  if (!privacyPolicyUrl.startsWith('https://')) {
    problems.add('PRIVACY_POLICY_URL must be an https:// address');
  }
  if (!mapStyleUrl.startsWith('https://')) {
    problems.add('MAP_STYLE_URL must be an https:// address (the disclosure names a map provider)');
  }
  if (googleServerClientId.isEmpty) {
    problems.add('GOOGLE_SERVER_CLIENT_ID is not set');
  }
  return problems;
}

/// The problems of this build's configuration (see [releaseConfigProblems]).
List<String> currentReleaseConfigProblems() => releaseConfigProblems(
      apiBaseUrl: AppConfig.apiBaseUrl,
      mapTileProvider: AppConfig.mapTileProvider,
      privacyPolicyUrl: AppConfig.privacyPolicyUrl,
      mapStyleUrl: AppConfig.mapStyleUrl,
      googleServerClientId: AppConfig.googleServerClientId,
    );
