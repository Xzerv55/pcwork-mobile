=== PCWork Mobile – Complete System ===
Contributors: pcwork
Tags: repairs, mobile, authentication, integrations
Requires at least: 6.0
Requires PHP: 7.4
Stable tag: 2.1.0
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
