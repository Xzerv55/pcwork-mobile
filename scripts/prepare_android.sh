#!/usr/bin/env bash
set -euo pipefail

# Generate the native Android host project with a stable PCWork application ID.
flutter create --platforms=android --org com.pcworkbg --project-name pcwork_mobile .

# flutter create generates a template test for MyApp; PCWork uses PCWorkApp.
rm -f test/widget_test.dart
rmdir test 2>/dev/null || true

python3 - <<'PY'
from pathlib import Path
manifest = Path('android/app/src/main/AndroidManifest.xml')
if manifest.exists():
    text = manifest.read_text()
    import re
    text, count = re.subn(r'android:label="[^"]*"', 'android:label="PCWork"', text, count=1)
    if count:
        manifest.write_text(text)

gradle_candidates = [Path('android/app/build.gradle.kts'), Path('android/app/build.gradle')]
for gradle in gradle_candidates:
    if not gradle.exists():
        continue
    text = gradle.read_text()
    if gradle.suffix == '.kts':
        text = text.replace('minSdk = flutter.minSdkVersion', 'minSdk = 23')
    else:
        text = text.replace('minSdkVersion flutter.minSdkVersion', 'minSdkVersion 23')
    gradle.write_text(text)
PY
