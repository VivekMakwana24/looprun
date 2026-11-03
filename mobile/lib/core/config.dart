/// Build-time configuration, supplied with --dart-define.
class AppConfig {
  static const String apiBaseUrl =
      String.fromEnvironment('API_BASE_URL', defaultValue: 'http://10.0.2.2:8000');
  static const bool devAuth = bool.fromEnvironment('DEV_AUTH', defaultValue: false);
  static const String googleServerClientId =
      String.fromEnvironment('GOOGLE_SERVER_CLIENT_ID', defaultValue: '');
  static const String mapStyleUrl = String.fromEnvironment(
    'MAP_STYLE_URL',
    defaultValue: 'https://demotiles.maplibre.org/style.json',
  );

  /// H3 resolution used by the server for cells.
  static const int h3Resolution = 10;
}
