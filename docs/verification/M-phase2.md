# Mobile phase 2 report (architecture refactor)

Date: 2026-11-04. Builder: Claude (Sonnet 5.5), session https://claude.ai/code/session_01NnDGzpM4KuLBR8myW3FwyX.
Scope: `mobile/` refactored to `docs/MOBILE_ARCHITECTURE.md`, plus Stop action in the notification, report-a-cell/run, the `/live` WebSocket, and the F11 CI check.
`engine/` and `server/` were not touched.

Nothing was compiled locally (no Flutter/Dart SDK in this workspace). Every claim about compiling or passing is from GitHub CI.

## CI state

All four jobs green on commit dce470c (run 41870971355): Python, Integration, Docker, and Flutter (pub get, build_runner, analyze, test, debug APK, and the new F11 manifest step).
`flutter analyze --no-fatal-infos` reports 24 infos and no warnings or errors (mostly `prefer_initializing_formals` on constructors that keep private fields; left alone on purpose).
The first run of the F11 step (on the previous commit) failed for a good reason that was a false positive: the merged manifest keeps our XML comment "Deliberately NOT requested: ACCESS_BACKGROUND_LOCATION". The script now matches the full name `android.permission.ACCESS_BACKGROUND_LOCATION`, and the independent `aapt2 dump permissions` check of the APK had already passed. The step has been seen failing (on that false positive) and passing; it has not been seen catching a real hit in CI, only in a local test with a fabricated manifest.
Earlier in the phase: a first push failed `analyze` on two `top_level_cycle` errors (providers referring to each other), fixed with explicit provider types.

## What changed

Layers (see `docs/MOBILE_ARCHITECTURE.md`, folder layout updated):

- **domain/recorder/**: `run_recorder`, `gps_health`, `geo` moved here unchanged (plus `PathPoint`). Pure Dart.
- **data/services/** (stateless wrappers, each with an interface and a fake in `test/fakes/fakes.dart`): `ApiService` (+ `DioApiService`), `LocationService`, `PermissionService`, `ForegroundService`, `GoogleAuthService`, `LiveService`, `TokenStore`.
- **data/db/**: `RunStore` interface + `DriftRunStore` (maps Drift rows to the `RunSummary` model, so no Drift type leaves the data layer).
- **data/repositories/**: `RunRepository` (owns the recorder session, write-first fixes, crash recovery, upload retry, run report), `CellRepository` (REST cache + live socket + nearest-cell lookup + cell report + leaderboard), `AuthRepository`, `ProfileRepository` (home zones, freeze, delete account, disclosure flag), `LocationRepository` (permission state and one position for map and disclosure). They take services, never each other.
- **data/providers.dart**: all DI in one file; tests override providers with fakes.
- **ui/<feature>/**: `*_screen.dart` (view, only watches state and calls commands) + `*_view_model.dart` (Riverpod `Notifier`; `AutoDisposeNotifier` for the map so leaving it closes the socket). Old `features/` and `core/providers.dart` are gone.
- **router.dart**: `go_router` with one pure function `appRedirect` (unknown -> splash, signed out -> sign-in, signed in without disclosure -> disclosure, else home) and a `refreshListenable` driven by the auth and disclosure view models. The disclosure still always precedes the first permission prompt (test: `disclosure_test.dart`).
- **Models** are hand-written immutable classes with `==`/`hashCode` where compared (`UserRef`, `Cell`, `HomeZone`, `AuthSession`, `RunSummary`). No freezed, no Bloc.

New features:

- **Stop in the notification**: `NotificationButton(id: 'looprun_stop')`; the task handler's `onNotificationButtonPressed` calls `sendDataToMain`, the main isolate receives it through `addTaskDataCallback` (`initCommunicationPort()` in `main()`), and `RunRepository.stop()` runs. These APIs were checked against the flutter_foreground_task 11.0.3 sources on GitHub (master = 11.0.3), and the app compiles in CI, but **the button has not been tried on a device**.
- **Report**: `ApiService.report` (POST /v1/reports). "Report this cell" (tap near a cell on the map -> dialog -> reason) and "Report a problem with this run" (result screen). 429 shows "too many reports".
- **/live**: `SocketLiveService` uses `dart:io` `WebSocket` (no new package), sends `{"type":"auth","token":...}` as the first message (the token is not in the URL), parses `cell_changed`. `CellRepository` reconnects with backoff, stops on close code 4401, and reconnects when the visible box changes. The map redraws from `CellRepository.updates`.
- **F11**: `mobile/tool/check_manifest.sh`, run by a new CI step after the debug build. It scans every merged debug manifest under `build/app/intermediates` for the full name `android.permission.ACCESS_BACKGROUND_LOCATION` (fails if none is found, so it cannot pass vacuously) and also runs `aapt2 dump permissions` on the APK.
- `test/architecture_test.dart` turns the import rules of the architecture doc into tests.
- Small text fixes from `O1-C1-followups.md`: item 7 (Stop action), item 8 (report + /live), item 9 (zone toast now "Cells inside it never show your name"), item 10 (delete-account dialog mentions that cells pass to the strongest remaining player). Compliance docs (`tester-guide`, `foreground-service-declaration`, `README`) no longer say the notification has no Stop button.

## Deviations and decisions to review

1. **Dependency added: `go_router ^17.0.0`.** The scope asks for go_router, which was not in the verified set. 18.x depends on `material_ui`/`cupertino_ui` (new Flutter 3.44 split), so 17.x was chosen. All other dependencies and versions are unchanged (`flutter_riverpod` stays 2.6, `<3`).
2. `RunRepository` owns the recording session (not the view model), because view models may not touch services. This makes it the largest class (about 300 lines).
3. A `cell_changed` frame with `owner: null` is drawn grey (private): the wire format cannot tell "hidden" from "free". The next REST refresh (every camera idle) corrects a freed cell. A server field to tell them apart would remove this.
4. Taps on cells use `onMapClick` plus a nearest-cell lookup within 45 m of the cell centre (with `featureTapsTriggersMapClick: true`), not the circle-tap callback, whose API was not verified.
5. Pause is not offered in the notification (only Stop).

## What remains

- Device test (Gate 1): screen-off recording for 30 minutes on two phones, the notification Stop button, `/live` against a real server, and report calls.
- `MAP_STYLE_URL` / tile provider decision, Play Integrity, Crashlytics (need privacy-policy updates first), a run history screen, `pubspec.lock` commit.
- The live socket only reconnects while the map tab is open; there is no background sync by design.
- Unit tests exist for every repository and for the auth, map, run and profile view models; the disclosure, home and result view models are covered only through the widget tests and the architecture test.

## Fixes after the independent review (docs/verification/M-phase2-review.md)

Written after `git pull --rebase` onto 6b4075d. Still no Flutter SDK here: everything below was compiled and tested only by GitHub CI.

**B1 - /live socket leak (fixed).** `SocketLiveService.connect` is a `StreamController` with `onListen`/`onCancel`, no `async*`. Cancelling the subscription cancels the socket listener, closes the `WebSocket` and the `HttpClient` at once. The 15 s connect timeout (`HttpClient.connectionTimeout` plus a `.timeout` on `WebSocket.connect`) also closes a socket that completes late. A 30 s ping interval is set so a dead connection is noticed. Tests (`test/data/live_service_test.dart`) use a real loopback `HttpServer`/`WebSocketTransformer`: first frame is the auth message and the token is not in the URL; `cell_changed` parsing; cancel closes the server-side socket without any server frame; cancel while still connecting leaves no open socket; close code 4401 becomes `LiveClosedException(4401)`; connect timeout against a server that accepts TCP but never upgrades closes the connection. The map view model test now asserts that the socket has no listener after zoom-out (the fake used to hide the leak).

**B2 - data tied to the account (fixed).** Drift schema v2: `user_id` on `runs` and `fixes` (migration with `addColumn`; old rows get `''` and belong to nobody, so they are neither shown nor uploaded - pre-release data, accepted). `DriftRunStore` and `DriftUploadStore` take the current user id as a closure and add `user_id = ?` to every query and write; signed out means empty reads and refused writes. `wipe()` removes only the signed-in account's data. The upload queue takes the current user id, sends nothing while signed out, and stops the tick when the account changes (the check sits directly before the request, with no await in between, and the token is read when the request starts). Home zones moved to a per-user preference key (`home_zones_v2_<userId>`); the old shared key is deleted on first read. The location disclosure flag stays device-wide on purpose (it is about the phone's permission, not the account). The recent-runs and run-result streams re-subscribe when the account changes. Tests: `drift_user_scoping_test.dart` runs the real stores on in-memory SQLite (B cannot read/list/fetch/upload/modify/discard A's run, signed-out behaviour, wipe, queue never uploads A's run for B, account switch mid-tick, upgrade from schema 1), plus per-user zone tests in `profile_repository_test.dart`. Residual: if the account changes while an upload is in flight, that run's result is not saved (it stays queued and is re-sent later; uploads are idempotent). A sign-out in the middle of a recording makes further fix writes fail visibly instead of landing under another account.

**B3 - 401 handling (fixed).** The queue no longer marks a job failed on 401: the job stays as it was (no attempt counted), the tick stops, and the queue stays blocked until a new session (`resumeAfterAuth`, called from the auth change stream). The sign-out rule moved out of the `providers.dart` closure into `SessionExpiryPolicy` (pure Dart, `lib/data/auth/`): no sign-out while recording or within 30 s after a stop; such a 401 is remembered and `recheck()` (called by the upload ticker every 5 s) signs out when the run is over. `RunRepository.lastStoppedAtMs` feeds it. Tests: `session_expiry_policy_test.dart` (6 cases), queue 401 cases in `upload_queue_test.dart`, and `api_unauthorized_test.dart`, which goes through a real `Dio` with a fake `HttpClientAdapter` -> `DioApiService` -> policy -> queue (the 401 is produced by the HTTP layer, not by calling `expireSession()`).

**B4 - tests that can fail (fixed).** `MemoryStore` has a slow-disk mode (`holdFixWrites`). New `run_repository_test.dart` cases: recorder and UI do not move until the DB write finished (fails if the recorder is updated first); `stop()` waits for in-flight writes and keeps the last points (fails if `Future.wait(_pending)` is removed: the run would be discarded as too short); `stop()` does not hang on a write that never ends (bounded wait, `pendingWriteTimeout`, 5 s by default); GPS stream end and GPS stream error. Socket and 401 coverage: see B1 and B3.

**Cheap items done.** F1: while the state is `stopping` the run screen shows a disabled "Saving..." button instead of Start. F2: a GPS stream that ends is reported as an error while recording (the run is not stopped). F8: `_teardown` guards each cancel so a failing one cannot stop the run from being saved. F12: after a reconnect `CellRepository` fetches the area again (only if the box is unchanged) to catch changes missed while the socket was down; the first connection does not refetch. Residual: a change that arrives while that fetch is in flight can be overwritten by the older snapshot until the next camera idle.

**Not done (deferred, same list as before):** F3-F7, F9, F10, F13-F26 of the review. F7 and F22 are the ones I would do next. A fix row stores its own `user_id` as requested; a fix written after the account changed mid-run is refused rather than reassigned.

**Not verified on a device:** everything in "What remains" above, plus the Drift migration on a real phone (the migration test runs on in-memory SQLite in CI).
