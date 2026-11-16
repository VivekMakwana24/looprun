#!/usr/bin/env bash
# Small patches on top of the generated Android scaffold. Argument: path to android/.
set -euo pipefail
ANDROID_DIR="${1:-$(cd "$(dirname "$0")/.." && pwd)/android}"
GRADLE=""
for f in "$ANDROID_DIR/app/build.gradle.kts" "$ANDROID_DIR/app/build.gradle"; do
  if [ -f "$f" ]; then GRADLE="$f"; break; fi
done
if [ -z "$GRADLE" ]; then
  echo "patch_android: no app/build.gradle(.kts) found in $ANDROID_DIR" >&2
  exit 1
fi
# maplibre_gl, flutter_foreground_task and geolocator all work with minSdk 24.
# Replace "minSdk = flutter.minSdkVersion" / "minSdkVersion flutter.minSdkVersion" with minSdk 24.
sed -i -E 's/minSdk(Version)?[[:space:]]*=?[[:space:]]*flutter\.minSdkVersion/minSdk = 24/' "$GRADLE"
echo "patch_android: patched $GRADLE"
grep -n "minSdk" "$GRADLE" || true

# Debug builds only: allow plain-HTTP to the local dev server (emulator -> http://10.0.2.2:8000).
# Android 9+ blocks cleartext traffic otherwise and the app shows "Network error". The release
# build is unaffected (this file lives in src/debug/ and is only merged into debug builds).
DEBUG_MANIFEST="$ANDROID_DIR/app/src/debug/AndroidManifest.xml"
mkdir -p "$(dirname "$DEBUG_MANIFEST")"
cat > "$DEBUG_MANIFEST" <<'XML'
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <!-- Debug only: lets the app reach the dev API over http:// -->
    <uses-permission android:name="android.permission.INTERNET" />
    <application android:usesCleartextTraffic="true" />
</manifest>
XML
echo "patch_android: wrote debug manifest with usesCleartextTraffic ($DEBUG_MANIFEST)"
