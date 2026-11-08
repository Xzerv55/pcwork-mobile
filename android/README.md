# Android host project

The Android Gradle host project is included in this source archive. `scripts/prepare_android.sh` only generates a host project if its Gradle build file is missing; it preserves an existing `android/app/google-services.json`.

Place the real Firebase configuration at `android/app/google-services.json`. The `.example` file is a template, not a working Firebase configuration.

Application ID: `com.pcworkbg.pcwork_mobile`. Version name and version code are read from `pubspec.yaml`.
