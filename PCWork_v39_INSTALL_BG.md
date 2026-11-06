# Инсталиране – PCWork Mobile v39

1. Изтеглете ZIP и разархивирайте.
2. Качете съдържанието в GitHub repository, като запазите `.github/workflows`.
3. Във Firebase Console → Project settings → Your apps → Android изтеглете `google-services.json`.
4. Качете файла точно в `android/app/google-services.json` (до `build.gradle` на app модула). Не използвайте `google-services.json.example`.
5. Уверете се, че Android package name във Firebase е `com.pcworkbg.pcwork_mobile`.
6. За iOS регистрирайте отделно iOS app със bundle ID `com.pcworkbg.pcwork_mobile`, настройте APNs authentication key/certificate във Firebase и добавете стойностите като GitHub Actions secrets.
7. В GitHub → Actions стартирайте `PCWork Android APK` или `PCWork iOS unsigned build`. Изчакайте `flutter analyze` и build стъпките да завършат.
8. Обновете WordPress плъгина до 2.9.0 чрез стандартния WordPress процес. Настройките се съхраняват в съществуващата опция.

## Firebase сигурност
Не качвайте service-account JSON ключове. `google-services.json` е клиентска Firebase конфигурация, но при публичен repository пак е разумно да ограничите API ключа чрез Firebase/Google Cloud API restrictions. Никога не публикувайте APNs private key или service-account credentials.


### Android Gradle
Архивът използва Gradle 8.14.3 и Android Gradle Plugin 8.9.1. Ако GitHub Actions все още показва Gradle 8.4, значи в GitHub не е качена обновената папка android/gradle и wrapper скриптовете от този архив.
