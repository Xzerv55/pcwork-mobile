# PCWork Mobile v59 – release notes

## Mobile fixes
- Centered the TikTok contact icon within its icon tile.
- Product images use a transparent image surface in the shop and cart; cart rows now show product thumbnails.
- The Support tab follows the selected light/dark theme, including the Chatway launch page.
- Chatway receives the signed-in customer's registered name, email and phone when Chatway Visitor Verification is configured.
- Hardened profile editing validation and added separate shipping first/last name fields.
- The profile update endpoint synchronizes WordPress and WooCommerce billing/shipping customer fields without allowing registration-email changes.
- Fixed Promotions and News saving by adding the missing authenticated WordPress REST endpoints.

## Previously planned items included
- Customer profile data remains the source for pre-filling WooCommerce checkout and is synchronized to WordPress/WooCommerce.
- GitHub Actions migrated to checkout@v5, setup-java@v5 and upload-artifact@v5 in both workflows.
- Existing repair, technician, service-location, push and reporting functionality retained.

## Build note
`pubspec.lock` is not included because Flutter/Dart tooling is not available in the authoring environment. GitHub Actions runs `flutter pub get` and generates/updates the lockfile during the build. No APK was generated in this environment.
