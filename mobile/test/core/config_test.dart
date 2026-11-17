import 'dart:io';

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:looprun/core/config.dart';
import 'package:looprun/core/theme.dart';
import 'package:looprun/data/services/google_auth_service.dart';

void main() {
  group('releaseConfigProblems (review F19)', () {
    List<String> check({
      String api = 'https://api.looprun.app',
      String tiles = 'ExampleTiles',
      String policy = 'https://looprun.app/privacy',
      String style = 'https://tiles.example.com/style.json',
      String google = 'x.apps.googleusercontent.com',
    }) =>
        releaseConfigProblems(
          apiBaseUrl: api,
          mapTileProvider: tiles,
          privacyPolicyUrl: policy,
          mapStyleUrl: style,
          googleServerClientId: google,
        );

    test('a complete configuration has no problems', () {
      expect(check(), isEmpty);
    });

    test('placeholders, the emulator address and plain http are all refused', () {
      expect(check(api: 'http://10.0.2.2:8000').single, contains('API_BASE_URL'));
      expect(check(tiles: AppConfig.tileProviderPlaceholder).single, contains('MAP_TILE_PROVIDER'));
      expect(check(policy: AppConfig.privacyPolicyPlaceholder).single, contains('PRIVACY_POLICY_URL'));
      expect(check(style: '').single, contains('MAP_STYLE_URL'));
      expect(check(google: '').single, contains('GOOGLE_SERVER_CLIENT_ID'));
    });

    test('the defaults of a plain debug build would not pass as a release', () {
      expect(currentReleaseConfigProblems(), isNotEmpty);
    });
  });

  test('the app's default Google web client is the one the dev server verifies against', () {
    final compose = File('../docker-compose.yml').readAsStringSync();
    final m = RegExp(r'LOOPRUN_GOOGLE_CLIENT_ID:\s*(\S+)').firstMatch(compose);
    expect(m, isNotNull, reason: 'docker-compose.yml no longer sets LOOPRUN_GOOGLE_CLIENT_ID');
    expect(AppConfig.googleServerClientId, m!.group(1));
    // Tests run in debug mode: the dev login is on unless DEV_AUTH=false was passed.
    expect(AppConfig.devAuth, isTrue);
  });

  group('googleSignInErrorMessage', () {
    test('ApiException 10 says the build is not set up, in plain words', () {
      final text = googleSignInErrorMessage(
        'sign_in_failed',
        'com.google.android.gms.common.api.ApiException: 10: ',
      );
      expect(text, googleNotSetUpMessage);
      expect(text, 'Google sign-in is not set up for this build yet');
    });

    test('a cancelled sign-in is silent', () {
      expect(googleSignInErrorMessage('sign_in_canceled', null), isNull);
      expect(
        googleSignInErrorMessage('sign_in_failed', 'com.google.android.gms.common.api.ApiException: 12501: '),
        isNull,
      );
    });

    test('network trouble and everything else get their own sentence, never the raw text', () {
      expect(googleSignInErrorMessage('network_error', 'ApiException: 7: '), googleNetworkMessage);
      expect(googleSignInErrorMessage('sign_in_failed', 'ApiException: 7: '), googleNetworkMessage);
      final other = googleSignInErrorMessage('sign_in_failed', 'ApiException: 8: internal');
      expect(other, googleFailedMessage);
      expect(other, isNot(contains('ApiException')));
      // 17 or 110 must not be read as 7 or 10.
      expect(googleSignInErrorMessage('sign_in_failed', 'ApiException: 17: '), googleFailedMessage);
      expect(googleSignInErrorMessage('sign_in_failed', 'ApiException: 110: '), googleFailedMessage);
    });
  });

  group('themes', () {
    test('every token of every theme equals the CSS of every mockup (docs/design)', () {
      final files = Directory('../docs/design').listSync().whereType<File>().where((f) => f.path.endsWith('.dc.html'));
      expect(files.length, 7);
      for (final file in files) {
        final css = parseThemeCss(file.readAsStringSync());
        expect(css.keys.toSet(), {'night', 'tartan', 'dawn', 'trail'}, reason: file.path);
        for (final id in AppThemeId.values) {
          final tokens = css[id.name]!;
          final colors = LooprunColors.of(id);
          expect(tokens.keys.toSet(), tokenNames.toSet(), reason: '${file.path} ${id.name}: token set');
          for (final name in tokenNames) {
            expect(hexOf(tokenOf(colors, name)), tokens[name], reason: '${file.path} ${id.name} --$name');
          }
        }
      }
    });

    test('buildTheme carries the tokens as a theme extension; only dawn is light', () {
      for (final id in AppThemeId.values) {
        final theme = buildTheme(id);
        expect(theme.extension<LooprunColors>(), same(LooprunColors.of(id)));
        expect(theme.scaffoldBackgroundColor, LooprunColors.of(id).bg);
        expect(theme.brightness.name, id == AppThemeId.dawn ? 'light' : 'dark');
      }
    });

    test('unknown stored names fall back to night', () {
      expect(themeIdFromName('trail'), AppThemeId.trail);
      expect(themeIdFromName('neon'), AppThemeId.night);
      expect(themeIdFromName(null), AppThemeId.night);
      expect(AppThemeId.values.map(themeLabel), ['Night', 'Tartan', 'Dawn', 'Trail']);
    });
  });
}

const List<String> tokenNames = [
  'bg', 'surface', 'raised', 'line', 'text', 'text2', 'muted', 'accent', 'accent-text', 'on-accent', 'rival', 'map',
  'park', 'road', 'lane', 'hid-fill', 'hid-line', 'paper', 'on-paper', 'dot', 'dot-ring', 'danger',
];

Color tokenOf(LooprunColors c, String name) {
  switch (name) {
    case 'bg': return c.bg;
    case 'surface': return c.surface;
    case 'raised': return c.raised;
    case 'line': return c.line;
    case 'text': return c.text;
    case 'text2': return c.text2;
    case 'muted': return c.muted;
    case 'accent': return c.accent;
    case 'accent-text': return c.accentText;
    case 'on-accent': return c.onAccent;
    case 'rival': return c.rival;
    case 'map': return c.map;
    case 'park': return c.park;
    case 'road': return c.road;
    case 'lane': return c.lane;
    case 'hid-fill': return c.hidFill;
    case 'hid-line': return c.hidLine;
    case 'paper': return c.paper;
    case 'on-paper': return c.onPaper;
    case 'dot': return c.dot;
    case 'dot-ring': return c.dotRing;
    case 'danger': return c.danger;
  }
  throw ArgumentError(name);
}

/// theme -> token -> "#RRGGBB" from the `.lr{...}` (night) and `.lr[data-theme="x"]{...}` blocks.
Map<String, Map<String, String>> parseThemeCss(String html) {
  final out = <String, Map<String, String>>{};
  final block = RegExp(r'\.lr(?:\[data-theme="(\w+)"\])?\{([^}]*)\}');
  for (final m in block.allMatches(html)) {
    final body = m.group(2)!;
    if (!body.contains('--')) continue;
    final tokens = <String, String>{};
    for (final d in RegExp(r'--([\w-]+):\s*(#[0-9A-Fa-f]{6})').allMatches(body)) {
      tokens[d.group(1)!] = d.group(2)!.toUpperCase();
    }
    out[m.group(1) ?? 'night'] = tokens;
  }
  return out;
}
