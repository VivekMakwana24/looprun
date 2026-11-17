# M-redesign review (independent verifier)

Date: 2026-11-17. Reviewed: main at d0d8a4a (commits 31b01b3..d0d8a4a, plus the server D10 commit 86b5d01), against
docs/design/*.dc.html, docs/MOBILE_ARCHITECTURE.md, docs/CONTRACT.openapi.yaml, docs/compliance/location-disclosure.md
and docs/verification/M-redesign.md. No Flutter SDK, no device: this is a code reading. CI (analyze, test, debug APK)
is green and was not re-run. Plugin behaviour was checked against the plugin sources (maplibre_gl 0.28.0 Android
`LayerPropertyConverter` / `MapLibreMapController`, geolocator_android `StreamHandlerImpl` / `FusedLocationClient`),
not on a phone.

**Verdict: accepted-with-fixes.** Two blockers, both small. Server D10 is correct and its tests are meaningful.
Privacy rules hold. Most device-only risks I could check against plugin sources look fine.

## Blockers (fix before device testing)

1. **CELLS HELD / THIS WEEK and the board stay stale for the whole session.**
   `mobile/lib/ui/leaderboard/leaderboard_view_model.dart:8-12` (`weeklyLeaderboardProvider`, autoDispose) feeds
   `myStandingProvider`, which the map (`map_screen.dart:177`) and Profile (`profile_screen.dart:132`) watch. It is only
   invalidated by the board's retry and pull-to-refresh (`leaderboard_screen.dart:36,108`).
   *Failure:* a tester runs their first loop and gets "42 CELLS CLAIMED", taps SEE IT ON THE MAP, and the map still
   says `--` or `0` CELLS HELD. The map page stays mounted under the root-navigator run/result routes, so the provider
   never loses its listener. Switching lanes does not help either: the next lane subscribes in the same frame, so the
   autoDispose provider is never dropped. The Board shows the same old answer until it is pulled.
   *Fix:* invalidate `weeklyLeaderboardProvider` when a run's result reaches a final state with `cells_claimed > 0`
   (the result view model or the upload queue's done callback), and when a live `cell_changed` frame changes a cell's
   `mine` flag. Also refresh it when the Board lane opens. Add a test: finish run -> accepted -> the map's stat changes.

2. **A failed run save leaves the live screen stuck on a disabled "SAVING…" button (regression).**
   `mobile/lib/data/repositories/run_repository.dart:310-315` emits `status: finished` with an error and no
   `finishedRunId` when `markFinished` throws. `run_screen.dart:40` counts `finished` as live, and `_Controls`
   (`run_screen.dart:402`) draws the disabled SAVING… button for it. The status chip reads SAVING RUN.
   *Failure:* the disk is full or Drift throws on finish. The runner sees "saving" that never ends, with only a small
   error line. The only way out is system back. The data itself is safe: the run stays `recording` in Drift and crash
   recovery offers it on the next launch. Before the redesign, this state showed the error and a Start button.
   *Fix:* treat `finished && finishedRunId == null && error != null` as a terminal error state. Show the error with a
   "Back to the map" button (or the `_NoRun` view, which already shows `run.error`). Add a widget test with a store
   whose `markFinished` throws.

## Checked and fine

- **Google sign-in:** `GoogleSignIn(serverClientId: <web client>)` in `google_auth_service.dart` is the correct 6.x
  Android usage (no google-services.json needed). The ID token goes to `POST /v1/auth/google` as `{id_token}`, and the
  server verifies `aud` against `LOOPRUN_GOOGLE_CLIENT_ID`. The dev compose file has the same web client id as the app
  default. The error mapping never shows raw text, and 7/10 are not confused with 17/110 (tested). Dev login is
  `!kReleaseMode && DEV_AUTH (default kDebugMode)`, and the server warns when dev auth and a Google id are both set.
  Still device-only: the Android OAuth client with each developer's debug SHA-1.
- **API base URL and cleartext:** the default is `http://10.0.2.2:8000`. `tool/patch_android.sh` writes
  `src/debug/AndroidManifest.xml` with `usesCleartextTraffic`, so it applies to debug builds only. A release build with
  a non-https API, placeholder values or no style URL shows the config-error app. The README covers `adb reverse` for
  real phones (compose binds 127.0.0.1).
- **MapLibre (0.28.0 sources):**
  - A style string starting with `{` is loaded with `Style.Builder().fromJson`.
  - The built-in style is valid v8 (one background layer, empty `sources`, no glyphs or sprite), so nothing is fetched.
  - `lineDasharray: [2.5, 2.5]` as a plain list is handled by `convertJsonToFloatArray`.
  - `['==', ['get','kind'], name]` filters are valid.
  - GeoJSON rings are `[lng, lat]` and closed. `hexOf` gives `#RRGGBB`.
  - A theme change re-keys the map. Sources and layers are re-added in `onStyleLoaded`, and the camera is carried over.
- **Theme persistence:** shared_preferences `looprun_theme_v1`, read in `ThemeViewModel.build`. Unknown values fall
  back to night.
- **go_router:** `appRedirect` is unchanged. The lanes form a ShellRoute, and record/result use the root navigator. The
  finish listener lives in HomeShell, which stays mounted under root routes.
- **Recorder:** the Drift write still comes before any UI or memory change (`_onFix`). Stopping is bounded:
  - cancel futures are no longer awaited;
  - pending writes wait at most 5 s;
  - a teardown error is caught.

  Recovery waits before `start()` (F5). Thinning to 20,000 fixes is fine: the integrity token is stored, not verified,
  and 20,000 fixes fit well under the 8 MB body limit.
- **Privacy:**
  - Disclosure strings in `disclosure_screen.dart` match location-disclosure.md, and the test enforces screen -> doc.
  - `strength` is computed only for the viewer's own cells (`cellview._own_strengths`), sent only when `mine`
    (REST uses `response_model_exclude_unset`, live checks `v["mine"]`), and the app drops it unless `mine`.
  - `_public_counts` passes no viewer, so no strengths there.
  - No route geometry reaches other players: the map draws cells only, and the loop painter shows the runner's own path.
  - Fonts are bundled (real TTFs, OFL), there is no google_fonts package, and `lib/` has no other http(s) URLs.
- **Server D10:**
  - `cell_boundary` matches h3.
  - `strength` is 1.0 in grace and while frozen. An expired, unsettled freeze is forgiven exactly as `settle_freeze`
    does (`updated += until - max(updated, started)` when `updated < until`). Reading it is read-only.
  - Leaderboard `me` ranks over all rows, and the caller's own count is fresh.
  - `GET /me` hides an expired `freeze_until`. `used_days` counts the running freeze only up to now and rounds up.
  - `POST /me/freeze` returns the same status shape.
  - The client's "days left = quota - used" is always allowed by `quota_ok`: every old interval ends by now, so a
    window ending at the new freeze's end holds no more old time than the current window.
  - Tests cover grace, half-life, refresh by re-running, a running freeze, an unsettled expired freeze, others not
    getting `strength`, the WS frame, `me` below the listed entries, and the quota window rolling off.

## Follow-ups

1. **`strength` resets to 1.0 at a freeze start** (`freeze.py` `rebase_for_freeze` + `strength`). A cell at 0.3 before
   rest days reads 1.0 during and after them, so the map's "N cells are fading" notice and the fading fill disappear
   although the hold is weak. D10 documents this, but the UX is misleading. Store a reference power (for example the
   power at the last claim) and divide by that.
2. **"Resets Monday" / "THIS WEEK" do not match the server.** `api.py:255-294` counts the cells held now (all cells,
   `count_documents({"owner_id": ...})`). The ISO week is only the cache key, so nothing resets on Monday. Either
   change the copy ("Cells held now") or make the board weekly.
3. **The map is rebuilt on every lane switch.** A plain `ShellRoute` disposes MapScreen, so each return:
   - recreates the MapLibre platform view;
   - restarts from the hard-coded Frankfurt camera (`cell_map.dart:41`);
   - reads the GPS position again and re-animates.

   Use `StatefulShellRoute.indexedStack`, or keep the camera in a provider.
4. **GPS restart only runs when the stream ends** (`_onFixesEnded`). With the fused client, "location switched off"
   arrives as an error and the stream stays open; updates resume by themselves when location comes back. Verify this
   on a device (Gate 1), including a device without Play services (LocationManager client).
5. **No unit tests for `ui/map/cell_geojson.dart`**, although it is pure Dart: `[lng, lat]` order, ring closure,
   `kind` names matching the layer filters, the point fallback, and that `builtInMapStyle` decodes with `sources` empty
   and no `glyphs`/`sprite`. With the canvas switched off in widget tests, nothing else covers this code.
6. **Tests that pass almost by construction:**
   - `config_test` "Google web client id has a default" asserts a constant.
   - The theme-token tests compare constants with hex values typed by the same author. Parse the `.lr{...}` CSS from
     docs/design the way the disclosure test reads the compliance doc.
   - The disclosure test checks screen -> doc only. It never checks that the Sharing paragraph is on screen, or that
     every doc string appears in the code.
7. **Malformed responses read as "Can't reach the server"** in `api_service.dart` `_guard`: a `TypeError` or
   `FormatException` becomes `ApiException(null)`, which `isNetwork` treats as no answer, so a server or contract bug
   looks like a connection problem. Use a distinct code or flag.
8. **"Other runners see your new cells in about 30 minutes"** is hard-coded, but the delay comes from
   `LOOPRUN_PUBLISH_DELAY_SECONDS`. Fine for now; it goes wrong as soon as the setting changes.
9. **Disclosure with a real `MAP_STYLE_URL`:** a third-party style can pull glyphs, sprites and tiles from more hosts
   than `MAP_TILE_PROVIDER` names. Check the release style before filling in the provider. In debug builds with no
   style URL, the screen names `[MAP_TILE_PROVIDER]` although nothing is loaded (acceptable for debug).
10. **Open review items** still not done: F13, F15, F21, F25.

## Fidelity vs the mockups (beyond the gaps the report already lists)

- **Main:**
  - The hint text, legend, stats and START RUN are all present.
  - The stats go stale (blocker 1).
  - The camera resets on every lane switch (follow-up 3).
  - The base map is a flat background with no streets, so a tester sees hexagons on a blank field.
- **Run:**
  - All mockup copy is present, including the 80 m rule (it matches the engine's `closure_tol_m`).
  - The save-failure state is wrong (blocker 2).
- **Result:**
  - Header, date, bib, splits (from the server only), taken band and notes are as mocked.
  - "short of your path" replaces the mockup's "short of your start" (justified).
  - The 30-minute text is fixed (follow-up 8).
- **Board:** layout and copy are as mocked, but the "Resets Monday" semantics are not true (follow-up 2).
- **Profile:** "Signed in" instead of "Signed in with Google". The radius and rest-day dialogs have no mockup.
- **Sign in / Disclosure:** copy matches. The extra dev block appears in debug builds only.
