#!/usr/bin/env bash
set -euo pipefail

# The Android Gradle host project is included in this archive.
# Keep android/app/google-services.json untouched when the user adds it.
# Generate a Flutter Android host only if the platform files are missing.
if [[ ! -f android/app/build.gradle.kts && ! -f android/app/build.gradle ]]; then
  FIREBASE_JSON="android/app/google-services.json"
  TMP_JSON=""
  if [[ -f "$FIREBASE_JSON" ]]; then
    TMP_JSON="$(mktemp)"
    cp "$FIREBASE_JSON" "$TMP_JSON"
  fi
  flutter create --platforms=android --org com.pcworkbg --project-name pcwork_mobile .
  if [[ -n "$TMP_JSON" ]]; then
    mkdir -p android/app
    cp "$TMP_JSON" "$FIREBASE_JSON"
    rm -f "$TMP_JSON"
  fi
fi
rm -f test/widget_test.dart
rmdir test 2>/dev/null || true
