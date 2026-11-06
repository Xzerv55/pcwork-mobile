=== PCWork Mobile – Complete System ===
Contributors: pcwork
Tags: repairs, mobile, authentication, integrations
Requires at least: 6.0
Requires PHP: 7.4
Stable tag: 3.3.0
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
* Repairs API – ремонти, статуси, локации, доказателства, протоколи, назначения.
* Repairs Admin – списък, филтри, история, документи, статус, техник, приоритет и срок.
* Admin Integration Settings – WooCommerce, Bookly, Chatway, Chaty, ShopLentor, Sheets, Firebase.
* Chaty – официален widget в приложението и административна проверка за активен плъгин/скриптове.
* Staff Management – присъствие, начало/край на смяна, заявки за отпуск и администраторско одобрение.
* Customer Management – списък на клиентите, email verification и блокиране/активиране на профили.
* OTP Security – шестцифрен код, 5-минутна валидност, 5 опита, resend cooldown и IP/email rate limits.

== Security ==
За протоколите и снимките задайте PCWORK_PRIVATE_DIR извън публичния web root. Използвайте HTTPS.

= 2.8.0 =
* Add working WordPress admin repairs page with filters, history, documents, status and technician assignment.
* Add Chaty mobile launch page, public configuration endpoint and admin integration check.
* Preserve the existing integration settings option and keys.

= 2.9.0 =
* Final integration release aligned with PCWork Mobile v39; preserves existing integration settings and repair API.

= 2.9.0 =
* Final integration release aligned with PCWork Mobile v39; preserves existing integration settings and repair API.

= 2.9.0 =
* Final integration release aligned with PCWork Mobile v39; preserves existing integration settings and repair API.

= 3.0.0 =
* Adds opt-in marketing push campaigns with scheduling, URL/image, targeting and campaign history.
* Preserves existing integration settings and repair notifications.

= 3.1.0 =
* Align plugin package version with PCWork Mobile v41.
* Keep the public service-location endpoint used by the nine-location mobile directory.
