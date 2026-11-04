#!/usr/bin/env bash
# F11: fails if the merged debug manifest (or the built APK) asks for ACCESS_BACKGROUND_LOCATION.
# Looprun records only while a run is active, in a foreground service, so it must never request it.
# Run after `flutter build apk --debug`. Argument: path to the mobile/ directory (default: parent of this script).
set -euo pipefail
MOBILE="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
PERM="ACCESS_BACKGROUND_LOCATION"
FOUND=0

mapfile -t MANIFESTS < <(find "$MOBILE/build/app/intermediates" -path '*merged_manifest*' -path '*ebug*' -name AndroidManifest.xml 2>/dev/null)
if [ "${#MANIFESTS[@]}" -eq 0 ]; then
  echo "check_manifest: no merged debug manifest found under $MOBILE/build/app/intermediates; the check would be vacuous" >&2
  find "$MOBILE/build/app/intermediates" -name 'AndroidManifest.xml' 2>/dev/null | head -20 >&2 || true
  exit 1
fi

for m in "${MANIFESTS[@]}"; do
  echo "check_manifest: scanning $m"
  # Sanity: the file we scan must be the merged one (it has our fine-location permission).
  if ! grep -q "android.permission.ACCESS_FINE_LOCATION" "$m"; then
    echo "check_manifest: $m does not contain ACCESS_FINE_LOCATION, so it is not the merged app manifest" >&2
    exit 1
  fi
  if grep -q "$PERM" "$m"; then
    echo "::error::$PERM found in merged manifest $m"
    grep -n "$PERM" "$m" || true
    FOUND=1
  fi
done

# Second opinion from the built APK itself, when the Android build tools are installed.
APK="$MOBILE/build/app/outputs/flutter-apk/app-debug.apk"
AAPT2="$(ls -1 "${ANDROID_HOME:-${ANDROID_SDK_ROOT:-/usr/local/lib/android/sdk}}"/build-tools/*/aapt2 2>/dev/null | tail -n 1 || true)"
if [ -f "$APK" ] && [ -n "$AAPT2" ]; then
  echo "check_manifest: scanning $APK with $AAPT2"
  if "$AAPT2" dump permissions "$APK" | grep -q "$PERM"; then
    echo "::error::$PERM found in $APK"
    FOUND=1
  fi
else
  echo "check_manifest: aapt2 or APK not available, skipped the APK scan"
fi

if [ "$FOUND" -ne 0 ]; then
  echo "check_manifest: FAILED. Find the library that adds it (see the manifest merger report) and remove it with tools:node=\"remove\" in android/app/src/main/AndroidManifest.xml." >&2
  exit 1
fi
echo "check_manifest: OK, $PERM is not requested"
