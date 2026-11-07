# PCWork Mobile v64 — 0.64.0+64

## Repair request reliability
- The customer repair form opens immediately while service locations load.
- Device type is no longer preselected; the only choices are Laptop, Desktop PC, PlayStation 5, PlayStation 4 and Other. Other requires a manual description.
- Problem description requires at least 15 meaningful characters; the form shows the error beside the field.
- A stable client request ID is retained across a retry. A network timeout is retried once with the same idempotency key to avoid duplicate repairs.
- The server accepts WooCommerce `customer` role accounts in addition to `pcwork_customer` and `subscriber`.
- Server-side validation enforces the device-type choices and meaningful problem-description length.

## Notifications
- The permission explanation is scheduled immediately after the first frame instead of waiting for WordPress session restoration.
- A versioned consent key allows the updated explanation to appear once after this release; Android system permission remains controlled by Android.
- Push registration now returns a success result; the profile includes a device/Firebase/marketing status check.
- WordPress exposes an authenticated push status endpoint.
- WooCommerce new-order notifications are sent to registered administrator/shop-manager/authorized staff devices, independent of customer marketing consent.
- Customer repair request confirmation push is sent to the customer's registered devices.

## Chatway identity
- Fixed the signed visitor identifier when Chatway is configured to verify by email: the identifier sent to Chatway now matches the value used to generate the server-side HMAC. The WordPress phone field still falls back to WooCommerce billing phone.

## Server refresh
- The profile refresh action now reloads the WordPress profile, marketing preference, repair list, API health and notification diagnostics.

## Compatibility
- Existing package ID, Firebase project options, signing configuration, API paths and persistent WordPress settings are retained.
- Keep the existing real `android/app/google-services.json` and existing release signing secrets.
