# PCWork Mobile v55

- Flutter app: `0.55.0+55`
- Unified WordPress plugin: `3.9.0` (`wordpress-plugin/pcwork-mobile-complete-system/`)
- Google Apps Script webhook: `2.6.0` (`google-apps-script/Code.gs`)
- Languages: Bulgarian / English
- Android package / iOS bundle ID: `com.pcworkbg.pcwork_mobile`

## v54 changes
- Vertically centers the existing bottom-navigation icon/label groups by removing the previous upward translation; all six destinations and icon sizes are preserved.
- Uses a signed URL-encoded `payload` field for Apps Script webhook requests, with matching fallback handling in `Code.gs`.
- Synchronizes repairs on creation and every supported save/update, including technician, priority and due-date changes; updates match the existing Repair ID.
- Normalizes common Firebase Service Account PEM copy/paste artifacts before OpenSSL parsing without exposing private key material.

## Build and deployment
- Run `flutter pub get`, `bash ./scripts/cleanup_legacy_chat.sh`, then `flutter analyze`.
- Build Android through the included GitHub Actions workflow. Keep the real `android/app/google-services.json` in the private project checkout; it is intentionally not included in this archive.
- Deploy `google-apps-script/Code.gs` as a new version of the existing Apps Script Web App deployment, preserving Script Properties and the `/exec` URL.
- Never commit or share Firebase Service Account private keys or the Google Sheets HMAC secret.

See `RELEASE_NOTES_v55.md` and `PCWork_v55_INSTALL_BG.md`.

## v55 changes
- Updated bottom navigation visual feedback and enlarged icons.
- Added an explicit in-app pre-permission explanation before the operating-system push prompt.
- Added separate, optional marketing opt-in/out controls in the customer profile.
