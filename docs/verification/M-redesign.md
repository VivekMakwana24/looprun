# M-redesign: "Night Track" app redesign (mobile)

Date: 2026-11-17. Source of truth: docs/design/*.dc.html (7 mockups). Server side (D10) was done before, in 86b5d01.
Commits: 965cb12 .. 3cc9c37 on main (plus the docs commit that adds this file).

**CI:** all four jobs green on the last code commit 3cc9c37 (run 44100057822): Python ruff+pytest, integration against
real MongoDB/Redis, Flutter (bootstrap, pub get, build_runner, `flutter analyze --no-fatal-infos`, `flutter test`,
debug APK, merged-manifest check for ACCESS_BACKGROUND_LOCATION), Docker build.

**Nothing in this report ran on a phone or an emulator.** "Done" below means: written, compiled, analyzed and covered
by unit/widget tests in CI. Widget tests render with Flutter's test font (square glyphs), not Barlow, and the map
canvas is switched off in them (`mapCanvasEnabledProvider`).

## Foundation

- Fonts: Barlow 400/500/600 and Barlow Condensed 500/600/700 + italic 600/700 declared in pubspec (bundled, OFL). No
  google_fonts, nothing downloaded.
- Themes: `LooprunColors` ThemeExtension with all 22 tokens per theme, values copied from the `.lr{...}` and
  `.lr[data-theme=...]` CSS blocks (night default, tartan, dawn light, trail); `buildTheme(id)` per theme;
  `ThemeRepository` (shared_preferences key `looprun_theme_v1`) + `ThemeViewModel`. `architecture_test` now fails on any
  colour literal under `lib/ui/` (the four swatch previews in Profile are fixed colours by design and live in
  `core/theme.dart` as `ThemeSwatch`).
- Shared widgets `ui/core/widgets.dart` (lane bar, boxes with >= 48 dp targets, big buttons, cards, stats, week chip,
  offline banner, message + retry, dashed outline, CapsLabel).
- Models for D10: `Cell.boundary` / `strength` (taken only when `mine`), `CellChange` boundary/strength,
  `Leaderboard.me`, `MeInfo`, `FreezeStatus` with quota; `ApiService.getMe`, `setFreeze` returns `FreezeStatus`.
- Routing: `ShellRoute` with lanes `/home` (1 MAP), `/board` (2 BOARD), `/you` (3 YOU); `/home/record` and
  `/home/run/:id` full screen on the root navigator. The redirect rule (`appRedirect`) is unchanged.

## Per screen

| Screen | What changed |
| --- | --- |
| Bottom nav | Three numbered lanes 1 MAP / 2 BOARD / 3 YOU, 62 px, active lane with a 3 px accent line and accent number, dividers. Board is its own route (the bottom-sheet leaderboard is removed). |
| Map (home) | MapLibre with one GeoJSON source and fill layers per kind: yours (accent), fading own cells (accent, 0.4), others (rival, 0.88), private (hidFill + dashed hidLine line layer); circle fallback for cells without boundary. Built-in background-only style in the theme's `map` colour when `MAP_STYLE_URL` is empty; map view rebuilt with the new style and colours on theme change (camera kept). Top: logo, week chip, CELLS HELD and THIS WEEK from leaderboard `me` (`--` while unknown), legend. Recentre button (48 dp, labelled). Sheet: offline banner, upload notice ("1 run is waiting to upload", failed uploads open the result), "N cells are fading / Run through them again to hold them" (only when N > 0, N = own cells in view with strength < 0.5), load error with retry, loading, empty/zoom notices; START RUN with "ON YOUR MARKS" and start-line ticks (becomes BACK TO RUN while a run is active); hint line (shows a start error instead when there is one). |
| Live run | Status chip RECORDING / PAUSED / SAVING RUN, GPS accuracy of the newest fix (or "Looking for GPS" / "GPS lost"), 124 px time, distance and pace (pace `--` under 50 m), "YOUR LOOP SO FAR" card (CustomPainter: dot grid, track, km markers, ringed start, dotted line to the nearest earlier point, head dot with halo), "<n> m to close the loop" or "Loop closed", rule line, controls pause + FINISH RUN / RESUME + FINISH / disabled SAVING..., lock-screen hint, a NO RUN state with the start error. Recorder rules kept (Drift write first, stopping state). |
| Result | Paper bib with pin holes: accepted (LOOP CLOSED + ACCEPTED chip, cells claimed in 168 px, accent band "N taken from other runners" when N > 0; "NO LOOP FOUND" when nothing was claimed), UNDER REVIEW / ON HOLD with the hard flag in the band, NOT COUNTED (rejected), RUN UPLOADED / COUNTING CELLS, SAVED ON THIS PHONE / UPLOADING or WAITING FOR A CONNECTION, UPLOAD FAILED + TRY AGAIN. 2x2 splits from the server only ("Not yet" before). Notes: `near_closure_repaired` as "You stopped N m short of your path, so we joined the gap for you." (N from the flag detail), other flags in plain words, "Other runners see your new cells in about 30 minutes." when cells were claimed. SEE IT ON THE MAP, report link. |
| Board | THE BOARD, week chip + "Resets Monday", "N cells to move up a lane / <name> holds lane L with C" only when the lane above the caller is listed, lane rows with bars relative to the leader, own row highlighted edge to edge (added below a "..." gap when the caller is not in the listed entries), footnote, empty and error (+ retry) states, pull to refresh, offline banner. |
| Profile (YOU) | Name, stats (same source as the map), 4-swatch theme picker (selected = accent border), home zones from `GET /me` (dashed ring, radius, remove per zone, "Add a zone where I am now" with a radius choice, "n of 5 used"), REST DAYS (= freeze) with "U of Q days used / in the last W days" bar from `GET /me`, start (choices limited to what is left) / end, 409 explained; Privacy Policy (browser), Sign out, Delete my account (danger). Offline: "Can't reach the server" row with retry. Sign-out and deletion refused during a run. |
| Disclosure | Same strings as docs/compliance/location-disclosure.md, headings and title in capitals by style only (`CapsLabel`, screen readers get the original string); timeline layout; keys `disclosure_agree_button` / `disclosure_decline_button` kept; the test now checks every on-screen string against the markdown file. Privacy Policy opens the browser. |
| Sign in | Track drawing, LOOPRUN, tagline, three numbered steps, paper "Sign in with Google" button, plain-language error under it, Privacy Policy link; dev login as a secondary block (debug builds only). |

## Login

- `GOOGLE_SERVER_CLIENT_ID` defaults to `623419287179-qsuu1f445he87kb6bomk1lp40fnmadk9.apps.googleusercontent.com`
  (Web client), still overridable.
- Errors: ApiException 10 -> "Google sign-in is not set up for this build yet"; 12501/12502/cancel -> nothing;
  network (7 or no server answer) -> "Can't reach the server. Check your connection." plus `Server: <API_BASE_URL>`
  in debug builds only; server 401/429/503/other -> own sentences. Raw PlatformException / Dio text is never shown.
- `DEV_AUTH` defaults to `kDebugMode` and is forced off when `kReleaseMode`.
- The debug cleartext manifest from `tool/patch_android.sh` is kept; README troubleshooting added (v1 embedding,
  ApiException 10, can't reach the server: bootstrap + full rebuild, API address, server up; note that compose binds the
  API to 127.0.0.1).

## Review items (docs/verification/M-phase2-review.md)

| Item | State |
| --- | --- |
| F3 paused notification | Fixed: "Paused. Open Looprun to resume or finish."; GPS stays on (stated). |
| F4 notifications denied | Fixed: run screen says the notification and Stop button are hidden; run still records. |
| F5 recovery vs quick Start | Fixed: `start()` awaits a running recovery check. Test. |
| F6 swipe from recents | Documented in the tester guide (behaviour unchanged). |
| F7 sign-out/delete during a run | Fixed: refused with a message. Test. |
| F8 stuck in stopping | Fixed: teardown and the write wait are guarded; stream cancel futures are no longer awaited (a widget test showed an awaited cancel can never resume). |
| F9 uploads give up offline | Fixed: no-answer errors retry for ever (5 min cap); server errors still give up after 12. Tests. |
| F10 413 over 20000 fixes | Fixed: evenly thinned before upload, first/last kept. Test. |
| F11 ticker only on home | Ticker now runs on all three lanes; tester guide says uploads need the app open. |
| F12 resync after reconnect | Was already fixed in phase 2. |
| F13 backoff reset only on a frame | Not done. |
| F14 handshake 403 retried for ever | Fixed: at most 8 reconnects in a row, then waits for the next camera stop. |
| F15 lifecycle pause of /live | Not done (ping interval was already set). |
| F16 repeated 4401 | Fixed: the refused token is not used again. |
| F17 clear-all redraw | Fixed: one GeoJSON source update per change. |
| F18 Privacy Policy link | Fixed: url_launcher (+ manifest `queries`), dialog fallback. |
| F19 release placeholders | Fixed: release builds with placeholders / non-https show a configuration error screen. Tests of the rule. |
| F20 stale docs | Disclosure doc (router, link) and tester guide updated. Privacy policy / data-safety answers not re-read. |
| F21 disclosure per device | Not done. |
| F22 service reaches into repositories | Was replaced by SessionExpiryPolicy in phase 2; a new cycle (upload queue reading the run repository) was found by a widget test and removed. |
| F23 architecture test on empty dirs | Fixed; plus rules for dart:io in domain, Flutter-free upload queue, no widgets in view models, no colour literals in ui. |
| F24 settle() timing | Improved: drains the event queue before a short real wait. Not removed everywhere. |
| F25 Drift store tests | Not extended (drift_user_scoping_test from phase 2 is the Drift coverage). |
| F26 debug cleartext | Was fixed before (patch_android.sh); kept. |

New tests: loop_gap_test (gap, crossing, wobble, downsampling, km marks), config_test (release rule, Google error
mapping, theme tokens), theme repository / view model, leaderboard view (lane-up, own row, empty), models for D10,
upload queue offline / thinning, run repository (GPS restart, give up, paused text, notifications off, accuracy,
recovery race), profile view model (GET /me, offline, remove, quota 409, refused during a run), auth errors,
screens_test (lanes, map numbers/fading/offline/upload notice/dashes, board, profile, result variants, live run states),
disclosure strings vs the compliance doc, sign-in copy and error.

## Not verified (needs a device)

- Anything MapLibre draws: the fill/line/circle layers, the `['==', ['get','kind'], ...]` filters, the dash array on
  the private outline, re-adding sources after a theme change, that the built-in JSON style loads, tap-to-cell.
- Google sign-in with the default web client and the debug SHA-1 Android client; the ApiException code parsing against
  the real plugin message format.
- url_launcher opening the browser; the release configuration screen in a real release build.
- GPS stream restart after location is switched off and on; notification texts; Stop button; lock-screen recording
  (Gate 1).
- Real font rendering, layout on small phones and with large system font sizes, contrast in each theme, TalkBack
  labels and order.
- Live updates carrying boundary/strength from the real server.

## Gaps vs the mockups

- Map: no parks/roads in the built-in style (background only, as instructed); with a real `MAP_STYLE_URL` the base map
  keeps its own colours and is not themed. The logo glyph and the GPS/pin/lock/close icons are Material icons close to
  the mockup SVGs, not the exact paths. The mockup's "Run the south edge within 2 days to hold it" is replaced by
  "Run through them again to hold them" (no invented edges or days). The lane bar is a separate bar under the sheet
  rather than drawn inside it (looks the same).
- Live run: the picture is the real path, so it does not look like the mockup's smooth curve; before 150 m the card
  says "Go / run out, then come back round" (no mockup for that state). "SAVING RUN" also shows while the finished run
  hands over to the result.
- Result: extra states not in the mockups (not counted, waiting for a connection, upload failed, no loop found); the
  loop icon is a Material icon; the joined-gap note says "short of your path" because the engine measures to the nearest
  earlier point, not the start; the "taken" band is hidden when it would say 0.
- Board: "Resets Monday" relies on the server's ISO week.
- Profile: says "Signed in" (the app cannot tell a Google from a dev session); radius and rest-day length are chosen in a
  small dialog (no mockup); the freeze end date is shown as "Resting until <day>" (no mockup).
- Sign in: the dev login block is extra (debug builds only).
