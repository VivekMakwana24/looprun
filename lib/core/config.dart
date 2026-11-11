/// Build-time configuration, supplied with --dart-define.
class AppConfig {
  static const String apiBaseUrl =
      String.fromEnvironment('API_BASE_URL', defaultValue: 'http://10.0.2.2:8000');
  static const bool devAuth = bool.fromEnvironment('DEV_AUTH', defaultValue: false);
  static const String googleServerClientId =
      String.fromEnvironment('GOOGLE_SERVER_CLIENT_ID', defaultValue: '');
  /// Shown in the location disclosure. Set both for release builds.
  static const String mapTileProvider =
      String.fromEnvironment('MAP_TILE_PROVIDER', defaultValue: '[MAP_TILE_PROVIDER]');
  static const String privacyPolicyUrl =
      String.fromEnvironment('PRIVACY_POLICY_URL', defaultValue: '[PRIVACY_POLICY_URL]');
  static const String mapStyleUrl = String.fromEnvironment(
    'MAP_STYLE_URL',
    defaultValue: 'https://demotiles.maplibre.org/style.json',
  );
}
