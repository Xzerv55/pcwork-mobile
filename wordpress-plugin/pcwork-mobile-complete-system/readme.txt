=== PCWork Mobile – Complete System ===
Contributors: pcwork
Tags: repairs, mobile, authentication, integrations
Requires at least: 6.0
Requires PHP: 7.4
Stable tag: 2.7.0
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

= 2.7.0 =
* Synchronize the mobile service directory with all nine entries currently published on /kontakti/.
* Preserve upcoming-opening labels and avoid inventing street addresses that are not published on the contact page.
* Cache repair and location data for offline viewing; queue repair intake and status changes for automatic retry.
* Add client request identifiers and database uniqueness constraints to prevent duplicate writes after interrupted requests.
