/// The four colour themes of the "Night Track" design (docs/design). Pure Dart.
enum AppThemeId { night, tartan, dawn, trail }

const AppThemeId defaultThemeId = AppThemeId.night;

/// The theme with this stored name, or the default for anything unknown.
AppThemeId themeIdFromName(String? name) {
  for (final id in AppThemeId.values) {
    if (id.name == name) return id;
  }
  return defaultThemeId;
}

/// Label shown under the swatch in Profile.
String themeLabel(AppThemeId id) {
  switch (id) {
    case AppThemeId.night:
      return 'Night';
    case AppThemeId.tartan:
      return 'Tartan';
    case AppThemeId.dawn:
      return 'Dawn';
    case AppThemeId.trail:
      return 'Trail';
  }
}
