import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:looprun/core/theme.dart';
import 'package:looprun/data/providers.dart';
import 'package:looprun/data/services/token_store.dart';
import 'package:looprun/ui/core/theme_view_model.dart';
import 'package:looprun/ui/map/map_view_model.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../fakes/fakes.dart';

/// Every fake a screen can need, so a widget test only says what differs.
class Harness {
  Harness() {
    store = MemoryStore();
  }

  final FakeApiService api = FakeApiService();
  final FakeLiveService live = FakeLiveService();
  final FakeLocationService location = FakeLocationService();
  final FakePermissionService permissions = FakePermissionService();
  final FakeForegroundService foreground = FakeForegroundService();
  final FakeGoogleAuthService google = FakeGoogleAuthService();
  final FakeLinkService links = FakeLinkService();
  late final MemoryStore store;
  StoredSession? session = const StoredSession(token: 't', userId: 'u1', userName: 'Vivek');
  bool devAuth = true;
  String policyUrl = 'https://looprun.example/privacy';
  late SharedPreferences prefs;

  Future<List<Override>> overrides() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    return [
      preferencesProvider.overrideWithValue(prefs),
      apiServiceProvider.overrideWithValue(api),
      liveServiceProvider.overrideWithValue(live),
      locationServiceProvider.overrideWithValue(location),
      permissionServiceProvider.overrideWithValue(permissions),
      foregroundServiceProvider.overrideWithValue(foreground),
      googleAuthServiceProvider.overrideWithValue(google),
      linkServiceProvider.overrideWithValue(links),
      runStoreProvider.overrideWithValue(store),
      uploadStoreProvider.overrideWithValue(store),
      tokenStoreProvider.overrideWithValue(InMemoryTokenStore(session)),
      devAuthEnabledProvider.overrideWithValue(devAuth),
      apiBaseUrlHintProvider.overrideWithValue(null),
      privacyPolicyUrlProvider.overrideWithValue(policyUrl),
      mapCanvasEnabledProvider.overrideWithValue(false),
    ];
  }
}

/// A phone-sized surface (360 x 800 logical pixels).
void usePhoneSize(WidgetTester tester) {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

/// Pumps [screen] inside the app's theme, signed in when the harness has a session.
Future<ProviderContainer> pumpScreen(WidgetTester tester, Harness h, Widget screen) async {
  usePhoneSize(tester);
  final overrides = await h.overrides();
  await tester.pumpWidget(ProviderScope(overrides: overrides, child: _Themed(child: screen)));
  final container = ProviderScope.containerOf(tester.element(find.byType(_Themed)));
  await container.read(authRepositoryProvider).restore();
  await tester.pump();
  return container;
}

class _Themed extends ConsumerWidget {
  const _Themed({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp(
      theme: buildTheme(ref.watch(themeViewModelProvider)),
      home: Scaffold(body: child),
    );
  }
}

/// Lets futures and stream events settle in a widget test without waiting on endless animations.
Future<void> pumpABit(WidgetTester tester, [int times = 5]) async {
  for (var i = 0; i < times; i++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}
