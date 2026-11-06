# PCWork Mobile v50 – release notes

## Flutter app
- Removed the obsolete Chaty screen/integration. Contact channels are provided directly by the app's Contact Hub.
- The delivered source contains no `chaty_screen.dart` and no calls to `ApiService.getChatyUrl()`.
- Kept the existing Chatway live-chat screen and secure WordPress session flow.
- Version: `0.50.0+50`.

## WordPress plugin
- Version `3.5.0`.
- Removed Chaty settings from the integrations page and settings sanitizer.
- Removed Chaty AJAX integration test, public `/chaty/config` REST route, plugin detection and Chaty launch page.
- Removed Chaty from the integration status response and dashboard description.
- Existing Chatway, Bookly, WooCommerce, Google Sheets, Firebase, ShopLentor, repairs, authentication and customer modules are retained.

## Firebase / Android
- Retains the v49 GitHub Actions approach: read Firebase client values from the real `android/app/google-services.json`, validate package name and pass values to Flutter at build time.
- The real JSON is not bundled. Keep it in the actual GitHub repository/workspace used by Actions.

## Validation
- PHP syntax and YAML syntax are checked for this package.
- ZIP integrity is checked.
- Flutter SDK is not available in this packaging environment; run `flutter analyze` and the Android GitHub Actions workflow to verify the actual Flutter build.
