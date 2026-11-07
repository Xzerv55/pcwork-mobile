# PCWork Mobile v62

Проектът съдържа Flutter приложението, Android/iOS конфигурацията, GitHub Actions workflow и единния WordPress плъгин.

## Компилация

1. Настройте четирите GitHub Actions Secrets за постоянно подписване според `SIGNING_SETUP_BG.md`.
2. Поставете реалния Firebase Android `google-services.json` в `android/app/` (не качвайте Service Account JSON в приложението).
3. Стартирайте GitHub Actions → PCWork Android APK → Run workflow.
4. Изтеглете артефакта `pcwork-android-v62-apks`.

Release APK се подписва само с постоянния release keystore. Ако липсват secrets, release компилацията спира, вместо да използва временен Debug сертификат.

## WordPress

Единният плъгин е в `wordpress-plugin/pcwork-mobile-complete-system/`. За отделно инсталиране използвайте ZIP архива на плъгина. Направете резервно копие и тествайте първо в staging.

## Бележки

- Android application ID: `com.pcworkbg.pcwork_mobile`.
- Версия: `0.62.0+62`.
- Не включвайте `.jks`, пароли, GitHub Secrets или Firebase Service Account private key в Git репозитория.
- Flutter SDK не е наличен в средата, в която е подготвен архивът; окончателният `flutter analyze` и Android build трябва да се потвърдят от GitHub Actions.
