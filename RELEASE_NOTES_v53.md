# PCWork Mobile v53 – release notes

## Flutter app 0.53.0+53
- Bottom navigation icon/label groups are no longer shifted upward; the existing icon size and six destinations are preserved so the group has balanced top and bottom spacing.

## Unified WordPress plugin 3.7.0
- Google Sheets now uses a signed URL-encoded `payload` POST field, which Apps Script can read from `e.parameter.payload` even when `e.postData.contents` is absent.
- Google Sheets synchronization listens to a canonical repair-saved event and is triggered for repair creation and subsequent edits, including technician, priority and due-date changes.
- Firebase private-key handling strips common copy/paste artifacts and rebuilds a canonical PEM block before OpenSSL parsing; private key contents are never logged.

## Google Apps Script Security 2.5.0
- Added a signed `payload` form-field fallback, safe diagnostics and preserved HMAC, replay protection, rate limiting and spreadsheet upsert behavior.

## Deployment note
The Apps Script file is included at `google-apps-script/Code.gs`. Replace the existing Apps Script source with this file, keep the existing Script Properties, then deploy a new version of the existing Web App deployment. Keep the same `/exec` URL and do not share the HMAC secret or Firebase private key.

## Verification limits
PHP syntax, archive integrity and workflow YAML are checked when available. Flutter compilation requires the Flutter SDK; if it is not installed in the build environment, use the included GitHub Actions workflow to produce the APK. A live Google Sheets write and live FCM delivery must be verified against the user's configured services.
