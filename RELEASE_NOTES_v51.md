# PCWork Mobile v51 – release notes

## Flutter app
- Added `scripts/cleanup_legacy_chat.sh`. It removes obsolete third-party chat screen files left over in an existing repository and checks that no matching Dart integration references remain before analysis/build.
- Both Android and iOS GitHub Actions workflows run the cleanup before `flutter analyze`.
- Android release builds use `--split-per-abi`, producing separate ARM64, ARMv7 and x86_64 APKs rather than one large universal release APK.
- Resized the in-app PCWork logo asset for its actual small UI display size. Launcher and splash artwork remain unchanged.
- Version: `0.51.0+51`.

## WordPress plugin
- Version: `3.6.0`.
- Removed remaining obsolete third-party chat widget integration code and related endpoints from the unified PCWork plugin.
- Retained Chatway, Bookly, WooCommerce, Google Sheets, Firebase, ShopLentor, repairs, authentication and customer modules.

## Firebase / Android
- Continues to read Firebase Android client configuration from the real `android/app/google-services.json` during GitHub Actions.
- The real JSON is not bundled. Keep it in the actual GitHub repository/workspace used by Actions. Never commit Firebase Service Account private keys.

## Validation notes
- PHP syntax, workflow YAML syntax, source cleanup checks and ZIP integrity are checked when packaging this release.
- Flutter/Dart SDK is not available in the packaging environment, so a real `flutter analyze` and Android/iOS build must still run in GitHub Actions.
