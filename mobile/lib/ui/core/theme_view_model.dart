import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_theme_id.dart';
import '../../data/providers.dart';

/// The active colour theme. The app and the map follow it; Profile changes it.
class ThemeViewModel extends Notifier<AppThemeId> {
  @override
  AppThemeId build() => ref.watch(themeRepositoryProvider).current();

  /// Switches at once and remembers the choice for the next launch.
  Future<void> select(AppThemeId id) async {
    if (id == state) return;
    state = id;
    try {
      await ref.read(themeRepositoryProvider).save(id);
    } catch (_) {
      // Not saved: the theme still applies until the app closes.
    }
  }
}

final themeViewModelProvider = NotifierProvider<ThemeViewModel, AppThemeId>(ThemeViewModel.new);
