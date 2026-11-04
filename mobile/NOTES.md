# Mobile notes

The cloud workspace has no Flutter/Dart SDK and pub.dev is blocked (docs/DECISIONS.md D4), so everything here is compiled,
analyzed and tested only by GitHub CI (phase 1 reached green at commit 71ec9ef; phase 2 status: docs/verification/M-phase2.md).
Package versions come from the verifier report docs/verification/M1-M2.md; `pubspec.lock` is not committed yet.

Architecture: docs/MOBILE_ARCHITECTURE.md (views + Riverpod notifier view models; repositories + stateless services; pure-Dart recorder in domain/).

## Design choices

- **Cells are drawn as coloured circles at the cell centre, not polygons.** The server sends `lat`/`lng` per cell (decision D7, `Cell.lat/lng`),
  so the app has no H3 dependency. Cells without lat/lng are skipped. Circle radius is in screen pixels. Colours: mine = green, others = orange,
  owner hidden by privacy rules = grey. Free cells are not returned by `GET /v1/cells`. Tapping near a cell opens a small dialog with a "Report this cell" action.
- **Live updates:** `CellRepository` loads the visible box over REST, then opens `WS /v1/live?bbox=...` (`SocketLiveService`, plain `dart:io` WebSocket, no extra package) and sends `{"type":"auth","token":...}` as the first message. `cell_changed` frames update the cache. A frame without owner is drawn grey (private) until the next REST refresh, because hidden and free cells look the same on the wire. Reconnects with backoff; close code 4401 stops retrying. The socket closes when the map tab is left.
- **Location is read in the main isolate** with geolocator's position stream. `flutter_foreground_task` runs a service (type `location`) that only
  keeps the process alive and shows the notification. The notification has a **Stop** button: the task handler's `onNotificationButtonPressed`
  sends a message to the main isolate (`initCommunicationPort`, `addTaskDataCallback`), where `RunRepository.stop()` runs. Needs a device test (Gate 1). It is started only from the Run screen's Start button,
  after location permission; the start result is checked and a failure aborts the run (row discarded).
- **Permissions** go through `data/services/permission_service.dart` (`PermissionService`): geolocator for location, `FlutterForegroundTask.requestNotificationPermission()` for notifications. `permission_handler` is gone.
- **Disclosure before permissions:** the go_router redirect (`appRedirect` in `lib/router.dart`) sends a signed-in user to `DisclosureScreen` until accepted. Texts are constants in `disclosure_screen.dart`
  and match docs/compliance/location-disclosure.md. `MAP_TILE_PROVIDER` and `PRIVACY_POLICY_URL` are `--dart-define`s with placeholder defaults.
  There is no `url_launcher` (not in the verified dependency set), so the "Privacy Policy" button shows the URL in a dialog (selectable) instead of opening it.
- **Write-first recording (F1):** each fix is inserted into Drift first; only after the insert succeeds are the recorder (distance) and the UI updated.
  Recorder states: idle, recording, paused, stopping, finished. `stop()` moves to `stopping` (no new fixes), the controller awaits in-flight writes,
  then `finish()` and `markFinished`. The stored fix count (from Drift) decides whether a run is too short.
- **Crash recovery:** `HomeScreen` asks `RunRepository.findUnfinishedRun()` (which stops a leftover service first), then offers to finish and upload (or discard) a `recording`/`paused` run, unless this process is recording right now (F9).
  A 401 during an active run does not sign the user out (F10).
- **Upload queue** is pure Dart; state lives in the `runs` table. Ticked every 5 s while the home screen is open and after a run finishes. Retries network errors,
  408/425/429 and 5xx with exponential backoff (2 s doubling, 5 min cap, 12 attempts); other 4xx fail at once. Unexpected non-API errors fail only that job (F4). Polls every 3 s while `processing`.
- **Home zones** are also kept in shared_preferences because the API only offers "replace the list".
- **Reports:** `POST /v1/reports` via `ApiService.report`; "Report a problem with this run" on the result screen, "Report this cell" on the map.
- Not done: Play Integrity, downsampling above 20000 fixes, iOS, `pubspec.lock` commit (after first green CI), the production tile provider, a visible per-run history screen.
- Dependency added in phase 2: `go_router ^17.0.0` (18.x needs material_ui/cupertino_ui). Everything else is unchanged.

## Dependency set

Taken from docs/verification/M1-M2.md section 3 (read from package sources, pub solver not run): Dart ^3.12, Flutter >=3.44, riverpod 2.6 (not 3), drift 2.35 without
sqlite3_flutter_libs, geolocator 14, flutter_foreground_task 11.0.3, google_sign_in 6.3 (not 7), maplibre_gl >=0.27.1 <0.29.0 (JDK 21), flutter_secure_storage 11.2, flutter_lints 6.
Fallbacks if CI rejects: drift/drift_dev 2.31.0 + `sqlite3_flutter_libs ^0.5.24`; flutter_foreground_task 8.17.0 (old `onDestroy(DateTime)`, drop `allowAutoRestart`/`stopWithTask`/`serviceTypes`).

## Unverified APIs (still open; check first when CI fails)

Confirmed by the verifier from package sources (not by compiling): MapLibreMap / MapLibreMapController API as used, `trackCameraPosition`, `onStyleLoadedCallback`, `CircleOptions`,
foreground-task 11 `init`/`startService`/`ServiceRequestFailure`/`requestNotificationPermission`, geolocator `AndroidSettings`/`isMocked`, google_sign_in 6.3, secure storage API, dio.

1. **Drift generated code** (`app_database.g.dart`): names `RunsCompanion`, `FixesCompanion`, `RunRow`, `FixRow`, `_$AppDatabase` are expected from drift's rules; unknown until build_runner runs. `drift_dev` 2.35 needs analyzer 13/14 to support Dart 3.13.
2. **sqlite3 build hook** (drift 2.32+) compiles SQLite with the NDK on first build; see fallback above.
3. **ServiceRequestFailure.error** field name in `AndroidRunService.start` (read from source by the verifier for 11.x; not compiled).
4. `ForegroundServiceTypes.location` constant and `serviceTypes:` parameter on `startService` (11.x).
5. `flutter_lints 6` may report new lints; analyze is run with `--no-fatal-infos` but warnings fail.
6. `onStyleLoadedCallback: _refreshCells` passes a `Future<void> Function()` where `void Function()` is expected (legal in Dart).
7. Widget tests import `app.dart`, which pulls in `maplibre_gl` and Drift; they only need these to compile on the VM (UNKNOWN, plausible).
8. Manifest keeps `tools:replace="android:foregroundServiceType"` (harmless; plugin declares no service of its own).
9. The disclosure "Privacy Policy" link only shows the URL (no url_launcher).
