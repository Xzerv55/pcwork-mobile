# PCWork Mobile WordPress Plugin v4.5.0

- Added authenticated `/push/status` endpoint for device registration and Firebase configuration diagnostics.
- Customer campaign audience now includes WooCommerce `customer`, PCWork `pcwork_customer` and `subscriber` profiles that have explicitly opted in.
- Added WooCommerce `woocommerce_new_order` push notifications for administrator, shop-manager and authorized staff devices. These transactional alerts do not depend on customer marketing consent.
- Added customer repair request confirmation push notifications.
- Chatway Visitor Verification now signs the exact selected identifier (WordPress user ID or email) and sends that same identifier, preventing mismatches when Email ID mode is selected.
- Customer repair request endpoint now recognizes WooCommerce `customer` role accounts.
- WooCommerce `customer` accounts remain OTP-protected unless an administrator explicitly enables password login for that user.
- Device type validation now accepts only Laptop, Desktop PC, PlayStation 5, PlayStation 4, or a non-empty `Друго: ...` value.
- Problem description requires at least 15 non-whitespace characters.
- Existing OTP, password access, user settings, repair tables and Firebase credentials are preserved.
