#!/usr/bin/env bash
set -euo pipefail
PUBSPEC_VERSION="$(sed -n 's/^version: //p' pubspec.yaml | head -n 1)"
if [[ ! "$PUBSPEC_VERSION" =~ ^([0-9]+\.[0-9]+\.[0-9]+)\+([0-9]+)$ ]]; then
  echo "ERROR: pubspec.yaml must contain version: MAJOR.MINOR.PATCH+BUILD."
  exit 1
fi
EXPECTED_NAME="${BASH_REMATCH[1]}"
EXPECTED_BUILD="${BASH_REMATCH[2]}"
DART_BUILD="$(sed -n "s/.*defaultValue: \([0-9][0-9]*\)).*/\1/p" lib/app/pcwork_app.dart | head -n 1)"
API_BUILD="$(python3 - <<'PYVERSION'
import re
from pathlib import Path
match = re.search(r'clientBuild\s*=\s*(\d+)', Path('lib/services/api_service.dart').read_text())
print(match.group(1) if match else '')
PYVERSION
)"
if [[ "$EXPECTED_BUILD" != "$DART_BUILD" || "$EXPECTED_BUILD" != "$API_BUILD" ]]; then
  echo "ERROR: build number mismatch: pubspec=$EXPECTED_BUILD, app=$DART_BUILD, API=$API_BUILD."
  exit 1
fi
GRADLE_FILE="android/app/build.gradle.kts"
if ! grep -Fq 'rootProject.file("../pubspec.yaml")' "$GRADLE_FILE" || \
   ! grep -Fq 'versionCode = resolvedVersionCode' "$GRADLE_FILE" || \
   ! grep -Fq 'versionName = resolvedVersionName' "$GRADLE_FILE"; then
  echo "ERROR: Android Gradle must parse versionName/versionCode from the root pubspec.yaml."
  exit 1
fi
if ! grep -Fq 'versionMatch.groupValues[1]' "$GRADLE_FILE" || \
   ! grep -Fq 'versionMatch.groupValues[2].toIntOrNull()' "$GRADLE_FILE"; then
  echo "ERROR: Android Gradle version parser must map pubspec semantic version and build number."
  exit 1
fi
printf 'Validated PCWork version: %s+%s (Android versionName=%s, versionCode=%s)\n' "$EXPECTED_NAME" "$EXPECTED_BUILD" "$EXPECTED_NAME" "$EXPECTED_BUILD"
