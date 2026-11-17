import 'package:flutter/material.dart';

import 'app_theme_id.dart';

export 'app_theme_id.dart';

/// Font families declared in pubspec.yaml (bundled, never downloaded).
const String fontBody = 'Barlow';
const String fontCondensed = 'BarlowCondensed';

/// Design tokens of one theme. The values are copied from the `.lr{...}` CSS blocks in docs/design/*.dc.html.
/// Widgets take every colour from here (`context.lr`), never from literals.
@immutable
class LooprunColors extends ThemeExtension<LooprunColors> {
  const LooprunColors({
    required this.bg,
    required this.surface,
    required this.raised,
    required this.line,
    required this.text,
    required this.text2,
    required this.muted,
    required this.accent,
    required this.accentText,
    required this.onAccent,
    required this.rival,
    required this.map,
    required this.park,
    required this.road,
    required this.lane,
    required this.hidFill,
    required this.hidLine,
    required this.paper,
    required this.onPaper,
    required this.dot,
    required this.dotRing,
    required this.danger,
  });

  final Color bg;
  final Color surface;
  final Color raised;
  final Color line;
  final Color text;
  final Color text2;
  final Color muted;
  final Color accent;
  final Color accentText;
  final Color onAccent;
  final Color rival;
  final Color map;
  final Color park;
  final Color road;
  final Color lane;
  final Color hidFill;
  final Color hidLine;
  final Color paper;
  final Color onPaper;
  final Color dot;
  final Color dotRing;
  final Color danger;

  static const LooprunColors night = LooprunColors(
    bg: Color(0xFF0A0C0B),
    surface: Color(0xFF121513),
    raised: Color(0xFF181C19),
    line: Color(0xFF262C28),
    text: Color(0xFFF2F5EE),
    text2: Color(0xFFC9CFC8),
    muted: Color(0xFFA9B1A9),
    accent: Color(0xFFC8F560),
    accentText: Color(0xFFC8F560),
    onAccent: Color(0xFF0A0C0B),
    rival: Color(0xFFFF7A45),
    map: Color(0xFF0D100E),
    park: Color(0xFF111A13),
    road: Color(0xFF181D1A),
    lane: Color(0xFF222824),
    hidFill: Color(0xFF262C28),
    hidLine: Color(0xFF69726A),
    paper: Color(0xFFF2F5EE),
    onPaper: Color(0xFF0A0C0B),
    dot: Color(0xFFFFFFFF),
    dotRing: Color(0xFF0A0C0B),
    danger: Color(0xFFFF8A7A),
  );

  static const LooprunColors tartan = LooprunColors(
    bg: Color(0xFF170B09),
    surface: Color(0xFF22110D),
    raised: Color(0xFF2C1711),
    line: Color(0xFF40231B),
    text: Color(0xFFFBEFE9),
    text2: Color(0xFFE3CFC6),
    muted: Color(0xFFC2A69B),
    accent: Color(0xFFFF5B3A),
    accentText: Color(0xFFFF7A5C),
    onAccent: Color(0xFF170B09),
    rival: Color(0xFF8FD0FF),
    map: Color(0xFF1C0E0B),
    park: Color(0xFF24140F),
    road: Color(0xFF2B1812),
    lane: Color(0xFF3A2019),
    hidFill: Color(0xFF33201A),
    hidLine: Color(0xFF8C6F64),
    paper: Color(0xFFFBEFE9),
    onPaper: Color(0xFF170B09),
    dot: Color(0xFFFFFFFF),
    dotRing: Color(0xFF170B09),
    danger: Color(0xFFFFB4A6),
  );

  static const LooprunColors dawn = LooprunColors(
    bg: Color(0xFFF3EFE7),
    surface: Color(0xFFFFFFFF),
    raised: Color(0xFFF8F5EF),
    line: Color(0xFFDDD6C9),
    text: Color(0xFF15181A),
    text2: Color(0xFF3A4044),
    muted: Color(0xFF5C6368),
    accent: Color(0xFFFF5A1F),
    accentText: Color(0xFFB93A08),
    onAccent: Color(0xFF15181A),
    rival: Color(0xFF2F6BE6),
    map: Color(0xFFE9E4D8),
    park: Color(0xFFDCE5CF),
    road: Color(0xFFFFFFFF),
    lane: Color(0xFFDDD6C9),
    hidFill: Color(0xFFD9D3C7),
    hidLine: Color(0xFF7A746A),
    paper: Color(0xFF15181A),
    onPaper: Color(0xFFF3EFE7),
    dot: Color(0xFF15181A),
    dotRing: Color(0xFFFFFFFF),
    danger: Color(0xFFB3261E),
  );

  static const LooprunColors trail = LooprunColors(
    bg: Color(0xFF0C1411),
    surface: Color(0xFF121D18),
    raised: Color(0xFF18251F),
    line: Color(0xFF26372F),
    text: Color(0xFFEEF3EC),
    text2: Color(0xFFC7D2C8),
    muted: Color(0xFF9FB0A4),
    accent: Color(0xFFF6B93B),
    accentText: Color(0xFFF6B93B),
    onAccent: Color(0xFF0C1411),
    rival: Color(0xFF7FD8E8),
    map: Color(0xFF0F1814),
    park: Color(0xFF14241B),
    road: Color(0xFF1A2A22),
    lane: Color(0xFF22332B),
    hidFill: Color(0xFF22302A),
    hidLine: Color(0xFF6C8074),
    paper: Color(0xFFEEF3EC),
    onPaper: Color(0xFF0C1411),
    dot: Color(0xFFFFFFFF),
    dotRing: Color(0xFF0C1411),
    danger: Color(0xFFFF9A8A),
  );

  static LooprunColors of(AppThemeId id) {
    switch (id) {
      case AppThemeId.night:
        return night;
      case AppThemeId.tartan:
        return tartan;
      case AppThemeId.dawn:
        return dawn;
      case AppThemeId.trail:
        return trail;
    }
  }

  @override
  LooprunColors copyWith() => this;

  @override
  LooprunColors lerp(ThemeExtension<LooprunColors>? other, double t) {
    if (other is! LooprunColors) return this;
    Color c(Color a, Color b) => Color.lerp(a, b, t) ?? b;
    return LooprunColors(
      bg: c(bg, other.bg),
      surface: c(surface, other.surface),
      raised: c(raised, other.raised),
      line: c(line, other.line),
      text: c(text, other.text),
      text2: c(text2, other.text2),
      muted: c(muted, other.muted),
      accent: c(accent, other.accent),
      accentText: c(accentText, other.accentText),
      onAccent: c(onAccent, other.onAccent),
      rival: c(rival, other.rival),
      map: c(map, other.map),
      park: c(park, other.park),
      road: c(road, other.road),
      lane: c(lane, other.lane),
      hidFill: c(hidFill, other.hidFill),
      hidLine: c(hidLine, other.hidLine),
      paper: c(paper, other.paper),
      onPaper: c(onPaper, other.onPaper),
      dot: c(dot, other.dot),
      dotRing: c(dotRing, other.dotRing),
      danger: c(danger, other.danger),
    );
  }
}

/// The small preview of a theme in the Profile picker (fixed colours from docs/design/Profile.dc.html:
/// they show the other theme, so they cannot come from the active one).
@immutable
class ThemeSwatch {
  const ThemeSwatch({required this.fill, required this.border, required this.bar});
  final Color fill;
  final Color border;
  final Color bar;

  static ThemeSwatch of(AppThemeId id) {
    switch (id) {
      case AppThemeId.night:
        return const ThemeSwatch(fill: Color(0xFF0A0C0B), border: Color(0xFF3A413C), bar: Color(0xFFC8F560));
      case AppThemeId.tartan:
        return const ThemeSwatch(fill: Color(0xFF2C1711), border: Color(0xFF5A3226), bar: Color(0xFFFF5B3A));
      case AppThemeId.dawn:
        return const ThemeSwatch(fill: Color(0xFFF3EFE7), border: Color(0xFFBDB5A6), bar: Color(0xFFFF5A1F));
      case AppThemeId.trail:
        return const ThemeSwatch(fill: Color(0xFF121D18), border: Color(0xFF3A4F44), bar: Color(0xFFF6B93B));
    }
  }
}

/// "#RRGGBB" for MapLibre style properties.
String hexOf(Color c) {
  final v = c.toARGB32() & 0xFFFFFF;
  return '#${v.toRadixString(16).padLeft(6, '0').toUpperCase()}';
}

extension LooprunThemeContext on BuildContext {
  /// The active theme's tokens.
  LooprunColors get lr => Theme.of(this).extension<LooprunColors>() ?? LooprunColors.night;
}

/// Text styles of the design. Sizes are the CSS pixel sizes of the mockups (logical pixels here).
class LrText {
  const LrText._();

  /// Barlow (body). [height] is the CSS line-height.
  static TextStyle body(
    double size, {
    FontWeight weight = FontWeight.w400,
    Color? color,
    double? height,
    TextDecoration? decoration,
  }) {
    return TextStyle(
      fontFamily: fontBody,
      fontSize: size,
      fontWeight: weight,
      color: color,
      height: height,
      decoration: decoration,
      decorationColor: color,
    );
  }

  /// Barlow Condensed upright: small spaced labels such as "CELLS HELD". [tracking] is in em.
  static TextStyle label(
    double size, {
    FontWeight weight = FontWeight.w600,
    Color? color,
    double tracking = 0.16,
    double height = 1.2,
  }) {
    return TextStyle(
      fontFamily: fontCondensed,
      fontSize: size,
      fontWeight: weight,
      color: color,
      letterSpacing: size * tracking,
      height: height,
    );
  }

  /// Barlow Condensed bold italic: numbers and big titles.
  static TextStyle display(
    double size, {
    Color? color,
    double tracking = 0,
    double height = 0.95,
  }) {
    return TextStyle(
      fontFamily: fontCondensed,
      fontSize: size,
      fontWeight: FontWeight.w700,
      fontStyle: FontStyle.italic,
      color: color,
      letterSpacing: size * tracking,
      height: height,
    );
  }
}

/// Material theme for one Looprun theme. Material widgets that still appear (dialogs, snack bars, text fields)
/// pick their colours up from here, so they match the tokens too.
ThemeData buildTheme([AppThemeId id = defaultThemeId]) {
  final c = LooprunColors.of(id);
  final brightness = id == AppThemeId.dawn ? Brightness.light : Brightness.dark;
  final scheme = ColorScheme(
    brightness: brightness,
    primary: c.accent,
    onPrimary: c.onAccent,
    secondary: c.rival,
    onSecondary: c.onAccent,
    error: c.danger,
    onError: c.bg,
    surface: c.surface,
    onSurface: c.text,
    onSurfaceVariant: c.text2,
    outline: c.line,
    outlineVariant: c.line,
    surfaceContainerHighest: c.raised,
    surfaceContainerHigh: c.raised,
    surfaceContainer: c.surface,
    surfaceContainerLow: c.surface,
    inverseSurface: c.paper,
    onInverseSurface: c.onPaper,
  );
  final base = ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    fontFamily: fontBody,
    scaffoldBackgroundColor: c.bg,
    extensions: <ThemeExtension<dynamic>>[c],
  );
  final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(18));
  return base.copyWith(
    textTheme: base.textTheme.apply(bodyColor: c.text, displayColor: c.text),
    dividerColor: c.line,
    dialogTheme: DialogThemeData(
      backgroundColor: c.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(color: c.line),
      ),
      titleTextStyle: LrText.body(20, weight: FontWeight.w600, color: c.text),
      contentTextStyle: LrText.body(15, color: c.text2, height: 1.4),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: c.paper,
      contentTextStyle: LrText.body(15, weight: FontWeight.w500, color: c.onPaper),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: c.surface,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: c.accent,
        foregroundColor: c.onAccent,
        minimumSize: const Size(64, 50),
        shape: shape,
        textStyle: LrText.body(16, weight: FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: c.text,
        backgroundColor: c.raised,
        side: BorderSide(color: c.line),
        minimumSize: const Size(64, 50),
        shape: shape,
        textStyle: LrText.body(16, weight: FontWeight.w600),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: c.accentText,
        minimumSize: const Size(48, 48),
        textStyle: LrText.body(15, weight: FontWeight.w600),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: c.raised,
      labelStyle: LrText.body(15, color: c.muted),
      hintStyle: LrText.body(15, color: c.muted),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: c.line),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: c.line),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: c.accent, width: 2),
      ),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: c.accent),
  );
}

