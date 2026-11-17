# Looprun mobile (Flutter, Android first)

The phone records GPS and shows the map. The server decides loops, cells, ownership and cheating
(see `../docs/CONTRACT.openapi.yaml`).

> Status: this code was written in a workspace without a Flutter SDK. It has never been compiled,
> analyzed or run. Expect a first CI round of small fixes; see `NOTES.md` ("Unverified APIs").

## Build

Requires Flutter stable 3.47.x (Dart 3.12+), JDK 21 (maplibre_gl needs it), Android SDK.

```bash
cd mobile
bash tool/bootstrap.sh            # flutter create (android scaffold) + our manifest + patches
flutter pub get
dart run build_runner build --delete-conflicting-outputs   # Drift generates lib/data/db/app_database.g.dart
flutter analyze --no-fatal-infos
flutter test
flutter build apk --debug \
  --dart-define=API_BASE_URL=https://api.example.com \
  --dart-define=GOOGLE_SERVER_CLIENT_ID=<web client id>.apps.googleusercontent.com
```

Dev build (debug builds show the dev login under the Google button; the server must run with
`LOOPRUN_DEV_AUTH=1`):

```bash
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8000
```

## --dart-define options

| Name | Default | Meaning |
| --- | --- | --- |
| `API_BASE_URL` | `http://10.0.2.2:8000` | Server origin; `/v1` is appended. Release builds refuse anything but `https://` |
| `DEV_AUTH` | `true` in debug builds | Dev login (`id_token = "dev:<name>"`). Pass `false` to hide it in a debug build. Never available in release builds, whatever is passed |
| `GOOGLE_SERVER_CLIENT_ID` | `623419287179-qsuu...apps.googleusercontent.com` | OAuth client of type **Web application** (project of the dev server), so Google returns an ID token the server can verify |
| `MAP_TILE_PROVIDER` | placeholder | Name shown in the location disclosure (must be real in release) |
| `PRIVACY_POLICY_URL` | placeholder | Opened by the Privacy Policy links (must be `https://` in release) |
| `MAP_STYLE_URL` | empty | MapLibre style JSON URL. Empty = built-in plain style (background in the theme's map colour, no tiles, no map server contacted) |

A release build whose settings are missing or placeholders starts with a screen saying so instead of
the app (`releaseConfigProblems` in `lib/core/config.dart`).

Google sign-in on Android also needs an OAuth client of type Android (package `app.looprun.looprun`
plus the signing key SHA-1) in the same Google Cloud project. That is console configuration, not code.

## Troubleshooting

**"Build failed due to use of deleted Android v1 embedding"**
The `android/` folder is not complete: only `AndroidManifest.xml` is in git, the rest is generated.
Run `bash tool/bootstrap.sh` (from `mobile/`) before the first build and after every pull that
touches `android/` or `tool/`, then `flutter pub get` and build again.

**Google sign-in says "Google sign-in is not set up for this build yet"** (ApiException 10)
Google does not recognise this app for the web client id. In the Google Cloud project of
`GOOGLE_SERVER_CLIENT_ID` there must be an OAuth client of type **Android** with package name
`app.looprun.looprun` and the SHA-1 of the key that signed the APK (debug builds: the debug keystore of
the machine that built it, `keytool -list -v -keystore ~/.android/debug.keystore -alias androiddebugkey
-storepass android`). `GOOGLE_SERVER_CLIENT_ID` itself must be the **Web** client, not the Android one.
Console changes can take a few minutes. Closing the Google dialog is not an error and shows nothing.

**"Can't reach the server. Check your connection."** (was "Network error")
Debug builds print the server address under this message. Check, in this order:
1. The debug manifest that allows plain `http://` is missing: it is written by `tool/patch_android.sh`
   (run by `bootstrap.sh`). After pulling, run `bash tool/bootstrap.sh` again and do a full rebuild
   (`flutter clean` or stop the app and `flutter run` again; hot restart does not pick up manifest changes).
2. Wrong `API_BASE_URL`: the emulator reaches the host as `http://10.0.2.2:<port>`; a real phone needs
   the computer's LAN address (`http://192.168.x.y:<port>`) and both on the same network. Note that
   `docker-compose.yml` publishes the API on `127.0.0.1` only, so a real phone cannot reach it until you
   publish it on the LAN address (or use `adb reverse tcp:8000 tcp:8000` and `http://127.0.0.1:8000`).
3. The server is not up: `docker compose up` in the repository root, then open
   `http://localhost:8000/healthz` on the computer (`LOOPRUN_API_PORT` moves the port).

## Layout

See `../docs/MOBILE_ARCHITECTURE.md` for the rules. In short:

```
lib/core/          config, theme, formatting, AppException
lib/domain/recorder/ pure Dart: run state machine, GPS health, haversine
lib/data/          providers.dart (DI), services/, db/, repositories/, models/, upload/
lib/ui/            one folder per feature: *_screen.dart (view) + *_view_model.dart (Riverpod notifier)
lib/router.dart    go_router + appRedirect (signed out -> sign-in, no disclosure -> disclosure, else home)
test/              fakes/, domain/, data/, ui/, architecture_test.dart
tool/              bootstrap.sh, patch_android.sh, patch_signing.sh, check_manifest.sh
android/           only AndroidManifest.xml is ours; the rest is generated by bootstrap.sh
```

## Suggested CI steps

`bootstrap.sh` -> `flutter pub get` -> `build_runner build` -> `flutter analyze --no-fatal-infos` -> `flutter test` -> `flutter build apk --debug` -> `tool/check_manifest.sh` (fails if the merged manifest requests ACCESS_BACKGROUND_LOCATION).
