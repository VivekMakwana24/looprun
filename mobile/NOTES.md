# Mobile notes

The cloud workspace has no Flutter/Dart SDK and pub.dev is blocked (docs/DECISIONS.md D4), so everything here is compiled,
analyzed and tested only by GitHub CI (phase 1 reached green at commit 71ec9ef; phase 2 status: docs/verification/M-phase2.md).
Package versions come from the verifier report docs/verification/M1-M2.md; `pubspec.lock` is not committed yet.

Architecture: docs/MOBILE_ARCHITECTURE.md (views + Riverpod notifier view models; repositories + stateless services; pure-Dart recorder in domain/).

## Design choices

- **Visual design: "Night Track"** (docs/design/*.dc.html, redesign report docs/verification/M-redesign.md). Four themes
  (night default, tartan, dawn = light, trail). Every colour is a token of `LooprunColors` (a `ThemeExtension` in
  `lib/core/theme.dart`, values copied from the mockups' CSS); widgets read `context.lr`. `architecture_test` fails on a
  `Color(0x..)` or `Colors.*` (other than transparent) under `lib/ui/`. The chosen theme is kept in shared_preferences
  (`ThemeRepository`, `ThemeViewModel`). Fonts Barlow / Barlow Condensed are bundled (pubspec `fonts:`), never downloaded.
- **Navigation:** go_router `ShellRoute` with the lane bar (1 MAP `/home`, 2 BOARD `/board`, 3 YOU `/you`). The live run
  (`/home/record`) and a result (`/home/run/<id>`) are children of `/home` drawn on the root navigator, so a finished run
  `go`es to its result and back leads to the map. `HomeShell` does crash recovery, keeps the upload ticker alive on all
  three lanes and opens the result when a run finishes (also after the notification's Stop).
- **Cells are hexagons** from `Cell.boundary` (D10): one GeoJSON source, one fill layer per kind (yours, fading at 0.4,
  others at 0.88, private with a dashed line layer), a circle layer fallback for cells without a boundary
  (`ui/map/cell_geojson.dart`, `cell_map.dart`). One `setGeoJsonSource` per change (review F17). Fading = own cell with
  `strength < 0.5`; the notice counts those in view and is hidden at zero; no day estimates are shown.
- **Map style:** OpenFreeMap by default (no key): `positron` for dawn, `dark` for night/tartan/trail;
  `MAP_STYLE_URL` overrides. URLs checked (2026-11-18): hyperknot/openfreemap-styles README (HEAD 006ea57) names
  `https://tiles.openfreemap.org/styles/dark` and `/styles/fiord` ("dark" is the dark style, fiord a second one) and
  lists bright/liberty/positron/dark/fiord under `styles/`; hyperknot/openfreemap (HEAD 58e20d9) uses
  `https://tiles.openfreemap.org/styles/liberty` in `linux_host/deploy_linux_host.py` and links `/styles/bright` and
  `/styles/positron` in its docs; its README "Attribution" section requires "OpenFreeMap (c) OpenMapTiles Data
  from OpenStreetMap" and says MapLibre adds it automatically (attribution button kept enabled). The map view is
  rebuilt (keyed by theme) on a theme change, keeping the camera, and the hexagon layers are re-added after every
  style load, so they sit on top. maplibre_gl exposes no style-load error callback: a 20 s watchdog on
  `onStyleLoadedCallback` switches to the built-in plain style (background only) until the next theme change.
  Not verified on a device (no tiles reachable from the dev sandbox; tiles.openfreemap.org returned 403 to curl here).
  The phone's position is drawn as a dot only after it was read (map open, recentre), never tracked.
- **Sign-in track:** the accent arc now starts above the lane numbers (y ~202 vs numbers at 220-240) so it never
  crosses the "2"; docs/design/SignIn.dc.html draws it from the start line through the number (same bug in the mockup).
- **Numbers shown are the server's:** cells held / rank this week from leaderboard `me`; rest-day quota from `GET /me`;
  result splits from the run status. Unknown = `--` or "Not yet", never 0.
- **Loop gap** (`domain/recorder/loop_gap.dart`, pure Dart): distance from the newest point to the nearest earlier point
  that is at least 150 m back along the path and that the path left and came back to (path length >= 2x the straight
  line; the start always counts), "closed" within 80 m or when the path crosses itself (segments >= 150 m of path apart).
  The path is thinned (8 m spacing, at most 400 points) before drawing. A hint only; the server decides the loops.
- **Live updates:** `CellRepository` loads the visible box over REST, then opens `WS /v1/live?bbox=...` (auth as first
  message). Frames update the cache (boundary and own strength included). Reconnects with backoff, at most 8 in a row
  until the next camera stop (F14); a 4401 is remembered for that token (F16). Closes when the map lane is left.
- **Location is read in the main isolate** with geolocator's position stream; `flutter_foreground_task` only keeps the
  process alive and shows the notification with a **Stop** button (sent to the main isolate, `RunRepository.stop()`).
  If the GPS stream ends it is reopened after 2 s, at most 5 times in a row. Paused runs say "Paused" in the
  notification (F3). With notifications off the run screen says the notification is hidden (F4).
- **Permissions** via `PermissionService` (geolocator; notifications via flutter_foreground_task).
- **Disclosure before permissions:** the router redirect sends a signed-in user to `DisclosureScreen` until accepted.
  Strings are constants matching docs/compliance/location-disclosure.md; `disclosure_test` checks each one is in that file.
  Headings are capitals by style only (`CapsLabel`).
- **Privacy Policy links** open the browser (`url_launcher`, `LinkService`); if that fails or the URL is the placeholder,
  the address is shown in a dialog.
- **Write-first recording (F1):** each fix is inserted into Drift first; only then do recorder, distance and UI change.
  `stop()` -> `stopping` (no new fixes) -> teardown (cancel futures not awaited) -> wait at most 5 s for in-flight writes
  -> `finish` -> `markFinished`. Any failure on the way still leaves `stopping` (F8).
- **Crash recovery:** the shell asks `RunRepository.findUnfinishedRun()`; a Start pressed meanwhile waits for it (F5).
  Sign-out and account deletion are refused while a run is recorded (F7). A 401 during a run does not sign out.
- **Upload queue:** pure Dart, state in the `runs` table, ticked every 5 s while the main frame is open. No answer from
  the server (offline) is retried for ever with the delay capped at 5 min (F9); server errors 408/425/429/5xx give up
  after 12; other 4xx at once. Runs over 20000 fixes are thinned evenly before upload (F10).
- **Home zones:** the server list from `GET /me` replaces the phone copy when the profile opens; changes send the full list.
- **Login:** `GOOGLE_SERVER_CLIENT_ID` defaults to the dev project's Web client. Errors are sentences, never platform
  text (`googleSignInErrorMessage`, `signInErrorText`); debug builds add the API address to "Can't reach the server".
  `DEV_AUTH` defaults to on in debug builds and is forced off in release builds.
- **Release guard (F19):** a release build with placeholder or non-https settings shows a configuration error screen.
- Not done: Play Integrity, iOS, `pubspec.lock`, production tile provider, app lifecycle pause of the
  live socket (F15), per-user disclosure flag (F21), Drift-backed store tests (F25).

## Phase 1a: social surfaces

- **Navigation:** lanes stay 1 MAP, 2 BOARD, 3 YOU. The feed lives on BOARD as a hub with three tabs (FEED, RANKS, RIVALS), not a
  fourth lane: a fourth lane would crowd the numbered nav and the design has no slot for it, and the feed, the ranks and rivals are
  all "other runners". Search, rivals list, run detail and public profiles are full-screen pages above the shell.
  The inbox bell with the unread count sits on the map header (`/home/inbox`); the count refreshes when lane 1 is shown.
- **Layers:** services (`SocialApi`) -> repositories (user, feed, battle, notification, report; each takes only `ApiService`) ->
  Riverpod notifiers. `PagedViewModel` is the shared cursor list (`items`/`next_cursor`, refresh, load more, retry, optimistic
  replace/remove). `SocialActionsViewModel` holds follow/block/report/kudos calls and returns friendly outcomes.
- **Privacy:** run cards and detail never draw a route line, only the numbers. Names hidden by the server are shown as returned.
  Errors are read from `{"detail":{"code","message"}}` and mapped to sentences in `ApiException.friendlyMessage`.
- **Take it back:** the map sheet draws lost cells from their boundaries (`lr-lost` layer) and focuses the camera on them.
- **Unverified on a device:** the lost-cell layer, bell badge layout at large font scales, keyboard behaviour in the comment box.

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
6. `addGeoJsonSource` / `addFillLayer(filter:)` / `addLineLayer` / `setGeoJsonSource` of maplibre_gl 0.2x compile; their runtime behaviour (expression filters, dash arrays, re-adding layers after a style reload) is not verified on a device.
7. Widget tests import `app.dart`, which pulls in `maplibre_gl` and Drift; they only need these to compile on the VM (UNKNOWN, plausible).
8. Manifest keeps `tools:replace="android:foregroundServiceType"` (harmless; plugin declares no service of its own).
9. `url_launcher` 6.3 `launchUrl(..., mode: LaunchMode.externalApplication)` (compiled in CI; not run on a device).
