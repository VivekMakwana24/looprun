#!/usr/bin/env bash
# Generates the android/ Gradle scaffold with `flutter create`, then re-applies our
# AndroidManifest.xml and runs tool/patch_android.sh. Safe to run repeatedly.
set -euo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

MANIFEST="$HERE/android/app/src/main/AndroidManifest.xml"
cp "$MANIFEST" "$TMP/AndroidManifest.looprun.xml"

mkdir "$TMP/gen"
( cd "$TMP/gen" && flutter create --org app.looprun --project-name looprun --platforms android . )

mkdir -p "$HERE/android"
cp -R "$TMP/gen/android/." "$HERE/android/"
cp "$TMP/AndroidManifest.looprun.xml" "$MANIFEST"

bash "$HERE/tool/patch_android.sh" "$HERE/android"
echo "bootstrap done: now run 'flutter pub get'"
