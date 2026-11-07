# PCWork Mobile v65

Проектът съдържа Flutter приложението, Android/iOS конфигурацията, GitHub Actions workflow и единния WordPress плъгин v4.4.0.

## Компилация

1. Настройте четирите GitHub Actions Secrets за постоянно подписване според `SIGNING_SETUP_BG.md`.
2. Поставете реалния Firebase Android `google-services.json` в `android/app/` (не качвайте Service Account JSON в приложението).
3. Стартирайте GitHub Actions → PCWork Android APK → Run workflow.
4. Изтеглете артефакта `pcwork-android-v65-apks`.

Release APK се подписва само с постоянния release keystore. Ако липсват secrets, release компилацията спира, вместо да използва временен Debug сертификат.

## Основни поправки v65

- Работещо отваряне на редакцията на профила; регистрационният имейл остава заключен.
- Системно искане на разрешение за известия при първо стартиране; автоматична FCM регистрация след вход.
- Автоматично обновяване на профил, ремонти и маркетингово съгласие при напускане на раздел.
- Коректна Chatway Visitor Verification структура и автоматично подаване на име, имейл и телефон.
- Клиентските заявки за ремонт вече не чакат синхронно Google Sheets или FCM мрежови операции; те се изпълняват чрез WordPress Cron.
- Добавени оперативни push известия за нова заявка и нова WooCommerce поръчка, отделно от маркетинговото съгласие.

## WordPress

Единният плъгин е в `wordpress-plugin/pcwork-mobile-complete-system/`. За отделно инсталиране използвайте ZIP архива на плъгина. Направете резервно копие и тествайте първо в staging.

## Бележки

- Android application ID: `com.pcworkbg.pcwork_mobile`.
- Версия: `0.65.0+65`.
- Не включвайте `.jks`, пароли, GitHub Secrets или Firebase Service Account private key в Git репозитория.
- Flutter SDK не е наличен в средата, в която е подготвен архивът; окончателният `flutter analyze` и Android build трябва да се потвърдят от GitHub Actions.
