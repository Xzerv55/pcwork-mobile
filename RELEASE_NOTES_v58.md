# PCWork Mobile v58 — 0.58.0+58

## Customer profile and WooCommerce
- Fixed the customer profile editor and expanded it with billing and shipping address fields.
- Registration email is displayed as read-only and cannot be changed from the app profile or checkout.
- Authenticated profile API now returns WooCommerce billing/shipping data.
- Profile edits persist the address data to WordPress/WooCommerce customer metadata.
- Shop checkout pre-fills customer name, registration email, phone, billing address and shipping address from the saved profile.
- Checkout keeps billing and shipping addresses separate and persists the latest values to the customer profile for future orders.

## Settings and permissions
- App preferences save automatically when changed; removed the Save Settings button.
- WordPress API URL and its restore-default action are visible only to administrators.
- Added administrator-only visual preview modes for staff and customer screens. These do not change the account role or grant/revoke server permissions.
- Removed the language switch from Settings; the existing globe control remains the language switch.

## Notifications
- Replaced the nonfunctional notification setup action with a direct link to the app's notification settings in Android/iOS system settings.

## Existing project requirements carried forward
- GDPR entry on the home screen opens https://pcwork-bg.com/gdpr/.
- Service status remains limited to staff/admin accounts.
- Existing repair, booking, staff, service-location, WordPress API, Google Sheets, and Firebase integrations are retained.
- Support screen and Chatway fallback states now adapt to light and dark themes.
- Service-location selector uses a compact bottom inset while retaining scroll access to the final location card.
