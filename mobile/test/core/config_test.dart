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

  test('the Google web client id has a default and the dev login follows the build mode', () {
    expect(AppConfig.googleServerClientId, endsWith('.apps.googleusercontent.com'));
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
    test('every theme has its own tokens, copied from the mockups', () {
      expect(hexOf(LooprunColors.of(AppThemeId.night).accent), '#C8F560');
      expect(hexOf(LooprunColors.of(AppThemeId.night).bg), '#0A0C0B');
      expect(hexOf(LooprunColors.of(AppThemeId.tartan).accent), '#FF5B3A');
      expect(hexOf(LooprunColors.of(AppThemeId.tartan).accentText), '#FF7A5C');
      expect(hexOf(LooprunColors.of(AppThemeId.dawn).bg), '#F3EFE7');
      expect(hexOf(LooprunColors.of(AppThemeId.dawn).accentText), '#B93A08');
      expect(hexOf(LooprunColors.of(AppThemeId.dawn).paper), '#15181A');
      expect(hexOf(LooprunColors.of(AppThemeId.trail).accent), '#F6B93B');
      expect(hexOf(LooprunColors.of(AppThemeId.trail).map), '#0F1814');
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
