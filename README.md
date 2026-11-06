# PCWork Mobile v51

- Flutter app: `0.51.0+51`
- Unified WordPress plugin: `3.6.0` (`wordpress-plugin/pcwork-mobile-complete-system/`)
- Languages: Bulgarian / English
- Android package / iOS bundle ID: `com.pcworkbg.pcwork_mobile`

## v51 changes
- Added a build-time cleanup guard that deletes obsolete third-party chat source files left in an existing Git checkout and fails analysis if related Dart references remain.
- The current app retains the Contact Hub, direct phone/Viber/Messenger/TikTok links and the supported Chatway live-chat screen.
- Android release builds now produce separate APKs per CPU architecture to reduce the download size for each device.
- Reduced the in-app brand logo asset dimensions while retaining the original launcher and splash artwork.
- Updated the unified WordPress plugin to `3.6.0`; removed obsolete third-party chat widget integration code and kept the supported integrations.
- Retained the Firebase Android configuration flow that reads client values from `android/app/google-services.json` in GitHub Actions.

## Build
Run `flutter pub get`, `bash ./scripts/cleanup_legacy_chat.sh`, then `flutter analyze`. Build Android through the included GitHub Actions workflow. Keep the real `android/app/google-services.json` in the private project checkout; it is intentionally not included in this archive. Never commit Firebase Service Account private keys.

See `RELEASE_NOTES_v51.md` and `PCWork_v51_INSTALL_BG.md`.
