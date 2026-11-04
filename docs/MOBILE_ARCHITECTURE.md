# Mobile architecture (decision record, 2026-11-03)

Sources: Flutter's own "Guide to app architecture" and its "Architecture recommendations"
(docs.flutter.dev/app-architecture, read 2026-11-03).

## What the official guidance says (and how we apply it)

| Official recommendation | Strength | Our choice |
| --- | --- | --- |
| Separate a UI layer and a data layer | Strongly recommend | `lib/ui/` (views + view models) and `lib/data/` (repositories + services) |
| MVVM in the UI layer: passive views, logic in view models, one view model per view | Strongly recommend | Each screen has a Riverpod `Notifier`/`AsyncNotifier` as its view model, plus a widget that only renders state and calls commands |
| Repositories are the single source of truth; they never depend on each other | Strongly recommend | `RunRepository`, `CellRepository`, `AuthRepository`, `ProfileRepository`; they take services, never other repositories |
| Services wrap one data source and hold no state | (part of the above) | `ApiService` (Dio), `LocationService` (geolocator), `ForegroundService` (flutter_foreground_task), `AppDatabase` (Drift), `TokenStore` |
| Domain layer only when logic is complex or duplicated | Conditional | Yes, for exactly one thing: the recorder (`lib/domain/recorder/`, pure Dart, no Flutter imports) because it is the riskiest logic and must be unit tested alone |
| Immutable models | Strongly recommend | Plain immutable Dart classes with `==`/`hashCode` written by hand (no freezed: fewer generated files and build risks; Drift already needs `build_runner`) |
| Dependency injection, no globals | Strongly recommend | Riverpod providers are the DI container; tests override providers with fakes |
| Testing with fakes | Strongly recommend | Every service has an interface and a fake in `test/fakes/` |
| go_router for routing | Recommend | `go_router` with a redirect: signed out -> sign-in, no disclosure accepted -> disclosure, else home |
| Offline-first | Not covered by the guide | Our own rule, below |

## Why this suits Looprun specifically

1. **Local database is the source of truth for runs.** Every GPS fix is written to Drift before anything else. `RunRepository` exposes `Stream`s from Drift; the network is only a sync target (upload queue), so a dead network or killed app never loses a run.
2. **Server is the source of truth for the map.** `CellRepository` keeps an in-memory cache of the visible bbox, refreshed by REST and (later) the WebSocket; it never decides ownership.
3. **Recorder is a state machine in pure Dart** (`idle -> recording <-> paused -> finished`), fed fixes by `LocationService`, writing through `RunRepository`. The foreground service only keeps the process alive and shows the notification; location is read in the main isolate (simpler and testable). Gate 1 (30-minute screen-off test on two phones) decides whether this holds; the fallback is moving location reading into the service's task isolate behind the same `LocationService` interface.
4. **Why Riverpod, not Bloc or Provider:** compile-safe dependency injection, easy overriding in tests, and `AsyncNotifier` fits the loading/error/data states of the screens. Bloc would add ceremony for no gain at this size. We pin `flutter_riverpod` to a major version and do not use the Riverpod code generator.
5. **No clean-architecture use-case layer** beyond the recorder: it would add classes without removing complexity here.

## Folder layout

```
lib/
  main.dart, app.dart, router.dart   (go_router; appRedirect() is the one routing rule)
  core/            config, theme, formatting, AppException
  domain/recorder/ state machine, gps health, geo math (pure Dart)
  data/
    providers.dart Riverpod DI: services, stores, repositories (tests override these with fakes)
    services/      api_service (interface + Dio impl), location_service, permission_service,
                   foreground_service (notification Stop button), google_auth_service, live_service (/live WebSocket),
                   token_store
    db/            app_database (Drift), run_store (interface) + drift_run_store, connection
    repositories/  run_repository, cell_repository, auth_repository, profile_repository, location_repository
    models/        immutable models matching docs/CONTRACT.openapi.yaml, recording_snapshot, api_exception
    upload/        backoff, upload_queue (pure Dart, store behind an interface), drift_upload_store
  ui/
    core/          shared widgets (report dialog) and text helpers
    auth/ disclosure/ home/ map/ run/ run_result/ leaderboard/ profile/   (view + view_model per feature)
test/
  fakes/  domain/  data/  ui/  architecture_test.dart
```

Notes on where the guide's boxes landed:

- `RunRepository` owns the recorder session (start, pause, resume, stop, crash recovery, upload retry). View models never see a plugin.
- `LocationRepository` is the small read-only helper for the map and the disclosure screen (permission state, one position).
- Repositories take services and stores, never each other. `data/providers.dart` is the only place that wires them.
- View models are Riverpod `Notifier`s (`AutoDisposeNotifier` for the map, so leaving the map closes the live socket); views only watch state and call commands.

## Rules that CI and reviews enforce

- `ui/` never imports `data/services/` or `data/db/` directly; it talks to view models, which talk to repositories.
- `domain/` imports nothing from Flutter or from `data/`.
- Repositories do not import each other.
- No `BuildContext` in view models or repositories.
- Every repository and view model has a unit test using fakes.
- `test/architecture_test.dart` checks the import rules above, so CI fails when they are broken.
