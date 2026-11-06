# PCWork Mobile v52

- Flutter app: `0.52.0+52`
- Unified WordPress plugin: `3.6.1` (`wordpress-plugin/pcwork-mobile-complete-system/`)
- Languages: Bulgarian / English
- Android package / iOS bundle ID: `com.pcworkbg.pcwork_mobile`

## v52 changes
- Corrected the home-screen phone and TikTok cards to show only the service name and icon; the phone number and TikTok handle remain only in their launch actions.
- Adjusted the persistent bottom navigation bar spacing and lifted its existing icons slightly without reducing icon size.
- Kept transient overlays and sheets dismissible when switching main navigation sections.
- Improved Firebase service-account private-key normalization and OpenSSL RSA-SHA256 signing diagnostics. The private key is never logged or exposed.
- Invalidates the cached Firebase OAuth access token when integration settings are saved.
- Synchronized Flutter, README, GitHub Actions artifact labels and WordPress plugin versions.

## Build
Run `flutter pub get`, `bash ./scripts/cleanup_legacy_chat.sh`, then `flutter analyze`. Build Android through the included GitHub Actions workflow. Keep the real `android/app/google-services.json` in the private project checkout; it is intentionally not included in this archive. Never commit Firebase Service Account private keys.

See `RELEASE_NOTES_v52.md` and `PCWork_v52_INSTALL_BG.md`.
