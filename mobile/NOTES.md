# Mobile notes

Nothing in this directory has been compiled, analyzed or tested: the cloud workspace has no Flutter/Dart SDK
and pub.dev is blocked (docs/DECISIONS.md D4). Package versions are caret ranges chosen from memory;
exact resolution happens in CI (`flutter pub get`), and `pubspec.lock` is not committed yet.

## Design choices

- **Cells are drawn as coloured circles at the H3 cell centre, not as polygons.** Pure-Dart H3 boundary maths was judged too risky.
  The centre is computed by `lib/core/h3_cells.dart` using `h3_flutter` (calls are dynamic with fallbacks for API differences).
  If the package fails to load, cells are silently not drawn; the rest of the app works. Circle radius is in screen pixels, not metres.
  Colours: mine = green, others = orange, owner hidden by privacy rules = grey. "Free" cells are not returned by `GET /v1/cells`
  (only claimed cells), so free space is simply the bare map. The contract was not extended.
- **Location is read in the main isolate** with `geolocator`'s position stream. `flutter_foreground_task` runs a service
  (type `location`) whose only job is to keep the process alive and show the notification; its task handler does nothing.
  The service is started only from the Run screen's Start button, after location permission is granted.
- **Disclosure before permissions:** `AppGate` shows `DisclosureScreen` after sign-in until accepted. The permission prompts
  (location, then notifications) are triggered only by "Agree and continue" there. `ACCESS_BACKGROUND_LOCATION` is not requested.
- **Every fix is written to Drift immediately** (`fixes` table, includes `isMock`). A run is `recording`/`paused` until stopped,
  then `finished` with `upload = queued`. On app start `HomeScreen` offers to finish and upload (or discard) any unfinished run.
- **Upload queue** (`lib/data/upload/upload_queue.dart`) is pure Dart; state lives in the `runs` table (stage, attempts, next attempt time),
  so it survives restarts. Ticked every 5 s while the home screen is open and right after a run finishes. Retries network errors,
  408/425/429 and 5xx with exponential backoff (2 s doubling, 5 min cap, 12 attempts). Other 4xx (including 401, 413, 422) fail at once;
  the result screen shows a "Try again" button. While the server answers `processing`, it polls every 3 s.
- **Home zones** are also kept in shared_preferences because the API only offers "replace the list". Zones are placed at the current position.
- **Live path** on the Run screen is a `CustomPaint` polyline, not a map, to avoid a second platform view.
- Not done: WebSocket `/live`, reports, Play Integrity token (`integrity_token` is sent as null), downsampling when a run exceeds
  20000 fixes (the server would answer 413 and the run would show as failed), iOS.

## Unverified APIs (check first when CI fails)

1. `h3_flutter ^0.7.0`: that this version exists and resolves; `H3Factory().load()`; methods `cellToLatLng(BigInt)` or `h3ToGeo(BigInt)`;
   result fields `.lat` and `.lng`/`.lon`; that the Android native library is bundled. (lib/core/h3_cells.dart)
2. `maplibre_gl ^0.20.0`: widget class name `MaplibreMap` (newer releases rename it to `MapLibreMap` and the controller to `MapLibreMapController`);
   `onMapCreated`, `onCameraIdle`, `styleString`, `compassEnabled`, `controller.cameraPosition`, `getVisibleRegion()` returning bounds with
   `southwest`/`northeast`, `addCircles(List<CircleOptions>)`, `clearCircles()`, `animateCamera(CameraUpdate.newLatLngZoom(...))`,
   `CircleOptions` fields (`geometry`, `circleRadius`, `circleColor` as string, `circleOpacity`, `circleStrokeColor`, `circleStrokeWidth`). (lib/features/map/map_screen.dart)
3. `flutter_foreground_task ^8.10.0`: `FlutterForegroundTask.init(...)` parameter names; `AndroidNotificationOptions`, `NotificationChannelImportance.LOW`,
   `NotificationPriority.LOW`, `IOSNotificationOptions(showNotification, playSound)`, `ForegroundTaskOptions(eventAction, autoRunOnBoot, allowWakeLock, allowWifiLock)`,
   `ForegroundTaskEventAction.nothing()`; `TaskHandler` method signatures (`onStart(DateTime, TaskStarter)`, `onRepeatEvent(DateTime)`, `onDestroy(DateTime)`;
   v9 adds an `isTimeout` argument); `startService(serviceId, notificationTitle, notificationText, callback)`; `isRunningService` as a Future getter;
   `updateService`, `stopService`. Also whether `serviceTypes: [ForegroundServiceTypes.location]` must be passed on Android 14 in addition to the manifest. (lib/features/run/foreground_service.dart)
4. Manifest service class `com.pravera.flutter_foreground_task.service.ForegroundService` and `tools:replace="android:foregroundServiceType"` (android/app/src/main/AndroidManifest.xml).
5. `geolocator ^13.0.1`: `AndroidSettings(accuracy, distanceFilter, intervalDuration)`, `getPositionStream(locationSettings:)`,
   `getCurrentPosition(locationSettings:)`, non-null `Position.timestamp`, `Position.isMocked`, `LocationPermission.always/whileInUse`.
6. `google_sign_in ^6.2.1` (7.x has a different API): `GoogleSignIn(scopes:, serverClientId:)`, `signIn()`, `account.authentication.idToken`, `signOut()`.
7. `drift ^2.18.0`: generated `app_database.g.dart` (needs `build_runner`); `NativeDatabase.createInBackground(File)`; `LazyDatabase`;
   `getSingleOrNull`, `watchSingleOrNull`, `isIn`, `Value<String?>` in companions; `@DataClassName` names `RunRow`/`FixRow`.
8. `flutter_riverpod ^2.5.1`: `Notifier`/`NotifierProvider`, `AsyncValue.valueOrNull`, `overrideWithValue` on `Provider`. Riverpod 3 would break this; keep the 2.x pin.
9. `flutter_secure_storage ^9.2.2`: `FlutterSecureStorage()` constructor, `read/write/delete(key:)`.
10. `permission_handler ^11.3.1`: `Permission.notification.request()`. Needs no manifest entry beyond POST_NOTIFICATIONS.
11. `dio ^5.4.3`: `BaseOptions(contentType:)`, `DioException.response/message`.
12. `tool/patch_android.sh`: the sed pattern assumes the generated app Gradle file contains `minSdk = flutter.minSdkVersion` (or the Groovy equivalent).
    Generated `MainActivity` package is `app.looprun.looprun`; the manifest uses the relative name `.MainActivity`.
13. Lints: `flutter_lints ^4.0.0`; a few noisy lints are disabled in analysis_options.yaml. Run `flutter analyze --no-fatal-infos`.
14. Widget tests import `app.dart`, which pulls in `maplibre_gl`, `h3_flutter` and Drift code; they only need these to compile on the host VM, not to run.
