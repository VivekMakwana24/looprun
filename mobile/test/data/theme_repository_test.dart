import 'package:flutter_test/flutter_test.dart';
import 'package:looprun/core/app_theme_id.dart';
import 'package:looprun/data/repositories/theme_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('night is the default, and a saved choice is read back by a new repository', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final repo = ThemeRepository(prefs: prefs);
    expect(repo.current(), AppThemeId.night);
    await repo.save(AppThemeId.dawn);
    expect(prefs.getString(themePrefKey), 'dawn');
    expect(ThemeRepository(prefs: prefs).current(), AppThemeId.dawn);
  });

  test('a stored value that is no theme falls back to night', () async {
    SharedPreferences.setMockInitialValues({themePrefKey: 'purple'});
    final prefs = await SharedPreferences.getInstance();
    expect(ThemeRepository(prefs: prefs).current(), AppThemeId.night);
  });
}
