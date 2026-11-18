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

# Android Studio / IntelliJ project files. Without the Dart module file the IDE does not
# treat lib/ as part of the project and refuses to run lib/main.dart ("Entrypoint isn't
# within the current project"). Only copied when missing, so the user's own IDE settings
# are never overwritten. Delete .idea/ and looprun.iml and re-run to regenerate them.
for f in looprun.iml .idea; do
  if [ -e "$TMP/gen/$f" ] && [ ! -e "$HERE/$f" ]; then
    cp -R "$TMP/gen/$f" "$HERE/$f"
    echo "bootstrap: added IDE file $f"
  fi
done
echo "bootstrap done: now run 'flutter pub get'"
