import 'package:shared_preferences/shared_preferences.dart';

import '../../core/app_theme_id.dart';

const String themePrefKey = 'looprun_theme_v1';

/// The colour theme chosen on this phone (kept in shared_preferences; it is a device setting, not an
/// account setting, so it survives sign-out).
class ThemeRepository {
  ThemeRepository({required SharedPreferences prefs}) : _prefs = prefs;

  final SharedPreferences _prefs;

  /// The stored theme, or the default (night) when nothing or something unknown is stored.
  AppThemeId current() => themeIdFromName(_prefs.getString(themePrefKey));

  Future<void> save(AppThemeId id) async {
    await _prefs.setString(themePrefKey, id.name);
  }
}
