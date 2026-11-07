# PCWork Mobile WordPress Plugin v4.3.0

- Added public `/wp-json/pcwork/v1/app/update` release-manifest endpoint.
- Added administrator settings for latest app version, Android versionCode, HTTPS APK URL and release notes.
- Preserved OTP authentication, locked registration email profile updates, WooCommerce profile synchronization, repair workflow, staff APIs, FCM device management, Chatway server-side visitor verification and Google Sheets mirror.
- The endpoint returns only public update metadata and never exposes signing credentials or Firebase service-account secrets.
- Integration settings form now autosaves on field change (with a no-JavaScript fallback submit button).
