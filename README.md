# PCWork Mobile v68 source

Source baseline: v67. This release increments the Android/iOS app version to 0.68.0+68.

## Main changes
- First-party PCWork Chat replaces the external Chatway WebView.
- The chat uses authenticated WordPress REST endpoints and polls only while its tab is active (10-second interval).
- Text and image messages are supported; images are compressed on-device and capped at 5 MB.
- Chat notifications use the existing Firebase Cloud Messaging integration when push is enabled.
- Shop navigation is labelled Обяви / Listings.
- Language is automatic from the device locale by default, with Bulgarian and English overrides in Settings.
- Customer account role label is localized as Потребител / Customer.
- Removed the notification status check button from the profile.
- Service-location images are shown in a taller contain-fit area to avoid cropping.

## Build
Run `flutter pub get`, `flutter analyze`, then use the existing GitHub Actions release workflow. The real `google-services.json` and signing credentials must remain in protected GitHub secrets/environment. This source archive intentionally contains only `google-services.json.example`.

## Server
Install the unified WordPress plugin v5.0.0 from the separate plugin archive. The app requires that plugin version for the `/chat/messages` REST API.
