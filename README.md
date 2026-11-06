# PCWork Mobile v50

- Flutter app: `0.50.0+50`
- Unified WordPress plugin: `3.5.0` (`wordpress-plugin/pcwork-mobile-complete-system/`)
- Languages: Bulgarian / English
- Android package / iOS bundle ID: `com.pcworkbg.pcwork_mobile`

## v50 changes
- Completely removed Chaty from the WordPress plugin: admin settings, integration test, public REST endpoint and mobile launch page.
- Removed all Chaty app integration from the delivered Flutter source; direct contact channels remain in the app's Contact Hub/home screen.
- Fixed the stale Chaty screen build issue by excluding the obsolete `lib/screens/chaty_screen.dart` source; the app uses the current Contact Hub and Chatway implementation. If upgrading an existing Git checkout, delete any old `lib/screens/chaty_screen.dart` file and remove any stale import/reference before building.
- Retained the v49 Android Firebase configuration flow that reads client configuration from `android/app/google-services.json` in GitHub Actions.
- Retained automatic dismissal of transient routes when switching main sections.

## Build
Run `flutter pub get`, then `flutter analyze`. Build Android through the included GitHub Actions workflow. Keep the real `android/app/google-services.json` in the private project checkout; it is intentionally not included in this archive. Never commit Firebase Service Account private keys.

See `RELEASE_NOTES_v50.md` and `PCWork_v50_INSTALL_BG.md`.
