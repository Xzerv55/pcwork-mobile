=== PCWork Mobile – Complete System ===
Contributors: pcwork
Tags: repairs, mobile, authentication, integrations
Requires at least: 6.0
Requires PHP: 7.4
Stable tag: 2.5.0
License: GPLv2 or later

Единен WordPress плъгин за PCWork Mobile: вход и профили, сервизни ремонти, документи, протоколи, административни интеграции, присъствие на екипа и заявки за отпуск.

== Installation ==
1. Направете резервно копие.
2. Деактивирайте старите PCWork Mobile Auth Bridge, PCWork Mobile Repairs API и PCWork Admin Integration Settings.
3. Качете ZIP архива и активирайте този плъгин.
4. Проверете PCWORK_PRIVATE_DIR и служебните права.

== Modules ==
* Auth Bridge – email/password и bearer token.
* Repairs API – ремонти, статуси, локации, доказателства, протоколи, назначения.
* Admin Integration Settings – WooCommerce, Bookly, Chatway, Chaty, ShopLentor, Sheets, Firebase.
* Staff Management – присъствие, начало/край на смяна, заявки за отпуск и администраторско одобрение.

== Security ==
За протоколите и снимките задайте PCWORK_PRIVATE_DIR извън публичния web root. Използвайте HTTPS.

= 2.0.0 =
* Added native-app Chatway configuration endpoint and dedicated mobile chat page.
* Added Chatway Installation ID setting; API keys remain server-side and are not exposed to the app.

= 2.1.0 =
* Added authenticated, single-use Chatway launch tickets for logged-in app users.
* Added optional Chatway Visitor Verification using a server-side HMAC-SHA256 secret.
* Added selectable User ID or Email identifier; the verification secret is never returned to the mobile app.
* Added ticket expiry, one-time consumption, no-cache and no-referrer headers for the mobile chat page.

= 2.2.0 =
* Added secure PCWork mobile storefront routes for published WooCommerce products, product categories, customer order history and order creation.
* Product and category browsing is public; order creation and order history require a valid PCWork bearer session.
* Order creation validates product availability and stock, calculates configured shipping-zone rates, and returns the WooCommerce order payment URL.
* WooCommerce credentials remain server-side; the mobile app does not contain Consumer Key or Consumer Secret.

= 2.2.1 =
* Added automatic server-side Google Sheets upsert sync when a repair is created or its status changes.
* HMAC-SHA256 signed webhook payloads; secrets remain in WordPress.

= 2.2.2 =
* Improved Google Apps Script webhook diagnostics: follow redirects, validate the JSON ok flag, and display a sanitized response excerpt for HTTP/application errors.

= 2.2.3 =
* Centralized signed Google Sheets requests for both connection tests and repair synchronization.
* Explicitly follows the Google Apps Script ContentService 301/302/303 redirect to the one-time script.googleusercontent.com response URL using GET.
* Restricts redirect targets to HTTPS script.googleusercontent.com; does not replay the signed repair POST.
* Requires a valid JSON response with ok=true for successful synchronization.

= 2.4.1 =
* Login accepts WordPress email address or username using wp_authenticate and the site's normal authentication filters.
* Improved per-IP and per-account login throttling and clearer generic authentication errors.
* Preserved variable WooCommerce products, customer order details, and the v2.4.0 nonce-based Google Sheets HMAC integration with encrypted secret-at-rest settings.

= 2.5.0 =
* Resolve existing WordPress email addresses to their account login before authentication, while preserving normal WordPress authentication filters.
* Count failed authentication attempts only; successful sign-ins clear the corresponding counters.
* Reduce WooCommerce catalogue payloads by loading 20 products per request and fetching variable-product options only when a product is opened.
* Cache product categories for five minutes.
