import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:looprun/core/app_theme_id.dart';
import 'package:looprun/data/providers.dart';
import 'package:looprun/data/repositories/theme_repository.dart';
import 'package:looprun/ui/core/theme_view_model.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('starts with the stored theme, switches at once and stores the choice', () async {
    SharedPreferences.setMockInitialValues({themePrefKey: 'tartan'});
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(overrides: [preferencesProvider.overrideWithValue(prefs)]);
    addTearDown(container.dispose);

    expect(container.read(themeViewModelProvider), AppThemeId.tartan);
    final seen = <AppThemeId>[];
    container.listen(themeViewModelProvider, (previous, next) => seen.add(next));

    await container.read(themeViewModelProvider.notifier).select(AppThemeId.trail);
    expect(container.read(themeViewModelProvider), AppThemeId.trail);
    expect(seen, [AppThemeId.trail]);
    expect(prefs.getString(themePrefKey), 'trail');

    // Choosing the active theme again changes nothing.
    await container.read(themeViewModelProvider.notifier).select(AppThemeId.trail);
    expect(seen, [AppThemeId.trail]);
  });
}
