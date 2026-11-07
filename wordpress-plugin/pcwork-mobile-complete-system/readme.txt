=== PCWork Mobile – Complete System ===
Contributors: pcwork
Tags: repairs, mobile, authentication, integrations
Requires at least: 6.0
Requires PHP: 7.4
Stable tag: 4.3.0
License: GPLv2 or later

Единен WordPress плъгин за PCWork Mobile: вход и профили, сервизни ремонти, документи, протоколи, административни интеграции, присъствие на екипа и заявки за отпуск.

== Installation ==
1. Направете архив на сайта и базата данни.
2. Обновете съществуващия PCWork Mobile – Complete System плъгин; не инсталирайте втори екземпляр.
3. Проверете настройките в PCWork Mobile → Интеграции.
4. Отворете PCWork Mobile → Сервизни ремонти за управление на ремонтите.
5. Отворете PCWork Mobile → Клиенти за управление на клиентските профили.
6. Настройте и тествайте SMTP/WordPress пощата преди публично активиране на Email OTP.

== Modules ==
* Auth Bridge – email OTP registration/sign-in, customer role and bearer token.
* Repairs API – ремонти, статуси, локации, доказателства, протоколи, назначения и сервизен дневник за диагностика, работа, части, плащания и гаранции.
* Repairs Admin – списък, филтри, бутон „Нов ремонт“, клиентски профили, история, документи, статус, техник, приоритет и срок.
* Admin Integration Settings – WooCommerce, Bookly, Chatway, ShopLentor, Sheets, Firebase.
* Staff Management – присъствие, начало/край на смяна, заявки за отпуск и администраторско одобрение.
* Customer Management – списък на клиентите, email verification и блокиране/активиране на профили.
* OTP Security – шестцифрен код, 5-минутна валидност, 5 опита, resend cooldown и IP/email rate limits.

== Security ==
За протоколите и снимките задайте PCWORK_PRIVATE_DIR извън публичния web root. Използвайте HTTPS. Сервизният дневник прилага клиентски/служителски права и позволява отделно маркиране на записите, видими за клиента.

= 4.2.0 =
* Add repair worklog records for diagnostics, work performed, parts, payments and warranty.
* Add customer visibility control, repair cost/payment summary and warranty date.
* Notify customers by FCM when a new worklog record is marked visible to them.
* Keep existing location-scoped staff access and customer ownership checks.

= 2.8.0 =
* Add working WordPress admin repairs page with filters, history, documents, status and technician assignment.
* Preserve the existing integration settings option and keys.

= 2.9.0 =
* Final integration release aligned with PCWork Mobile v39; preserves existing integration settings and repair API.

= 3.0.0 =
* Adds opt-in marketing push campaigns with scheduling, URL/image, targeting and campaign history.
* Preserves existing integration settings and repair notifications.

= 3.1.0 =
* Align plugin package version with PCWork Mobile v41.
* Keep the public service-location endpoint used by the nine-location mobile directory.

= 3.6.0 =
* Remove obsolete third-party chat widget integration code and related endpoints.
* Keep direct contact channels in the mobile app and retain the supported live-chat module.
* Clean up plugin release notes and align the package version with the mobile app release at that time.

= 3.6.1 =
* Improve Firebase service-account PEM parsing and RSA-SHA256 JWT signing diagnostics.
* Normalize escaped PEM line breaks and clear cached OAuth tokens after integration settings are saved.

= 3.8.0 =
* Add an administrator repair creation form and optional new customer account creation.
* Trigger Google Sheets upsert on new customer requests, admin-created repairs, admin edits, and status updates.
* Preserve Firebase Service Account JSON exactly and validate private-key Base64 before OpenSSL parsing.
* Add a signed payload query fallback for Apps Script requests when postData is missing.
