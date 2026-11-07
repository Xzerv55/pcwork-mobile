# PCWork Mobile v65 – обновяване

## Какво съдържа
- Flutter приложение `0.65.0+65` (изходен код; APK не е включен).
- Единен WordPress плъгин `4.4.0`.
- Обновени GitHub Actions workflow файлове.

## 1. WordPress плъгин
1. Направете backup на сайта и базата данни.
2. В WordPress → Plugins обновете съществуващия **PCWork Mobile – Complete System** с `PCWork_Mobile_WordPress_Plugin_v4.4.0.zip`. Не активирайте второ копие.
3. Проверете в PCWork Mobile → Интеграции, че Firebase Push е включен и Project ID / Service Account JSON са валидни.
4. За Chatway включете Visitor Verification в Chatway, изберете същия идентификатор (User ID или Email ID) като в настройките на PCWork и поставете Security Key в WordPress. При смяна на типа идентификатор генерирайте нов Chatway ключ.
5. Уверете се, че WordPress Cron може да се изпълнява. Синхронизацията към Google Sheets и изпращането на push известия вече са изнесени във фонова задача, за да не блокират заявките към API. При силно ограничен/изключен WP-Cron настройте истински системен cron към `wp-cron.php`.

## 2. GitHub приложение
1. Архивирайте текущия repository.
2. Качете съдържанието на папката `PCWork_Mobile_App_v65` от този архив в `Xzerv55/pcwork-mobile`, като замените старите файлове.
3. Запазете реалния `android/app/google-services.json` в repository. ZIP архивът умишлено съдържа само `.example`, не реалния Firebase файл.
4. Запазете съществуващите четири signing secrets: `PCWORK_KEYSTORE_BASE64`, `PCWORK_KEYSTORE_PASSWORD`, `PCWORK_KEY_ALIAS`, `PCWORK_KEY_PASSWORD`. Не генерирайте нов keystore.
5. Стартирайте Actions → PCWork Android APK. Изчакайте стъпката **Analyze Dart code** и build да приключат.
6. Артефактът се казва `pcwork-android-v65-apks`.

## 3. Известия
- При първо стартиране Android показва системното разрешение, ако още не е дадено. Android запазва разрешението при обновяване; затова при вече разрешени известия няма да покаже втори диалог.
- След вход приложението регистрира FCM токена към текущия WordPress профил.
- Служебните известия за нова заявка/поръчка не зависят от маркетинговото съгласие. Промоционалните кампании се изпращат само до профили с изрично включено съгласие.

## 4. Важно за тестването
Този архив не съдържа APK. Flutter SDK не беше наличен в средата за подготовка, затова окончателният `flutter analyze` и Android build трябва да се потвърдят от GitHub Actions. PHP синтаксисът на всички файлове в плъгина е проверен локално; не е правен live тест срещу WordPress, WooCommerce, Firebase или Chatway.
