# Android platform scaffold

The Android host project is materialized from the Flutter SDK template by `scripts/prepare_android.sh` before CI builds. The script preserves `app/google-services.json` across regeneration. Put the real Firebase file at `android/app/google-services.json` (not the `.example` template).

Application ID: `com.pcworkbg.pcwork_mobile`.
