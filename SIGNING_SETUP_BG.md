# Постоянен подпис за PCWork Mobile v64

**Важно:** Файлът `.jks` е частният ключ за подписване. Не го качвайте в GitHub repository и не го изпращайте публично. Направете поне две резервни копия на сигурни офлайн места. Загубата му ще попречи на бъдещи актуализации със същия подпис.

## 1. Създаване на GitHub Actions secrets

В GitHub отворете repository `Xzerv55/pcwork-mobile` → Settings → Secrets and variables → Actions → New repository secret. Създайте точно тези четири secrets:

- `PCWORK_KEYSTORE_BASE64` — цялото съдържание на файла `PCWork_Mobile_Release_v61_BASE64.txt`.
- `PCWORK_KEYSTORE_PASSWORD` — стойността от `PCWORK_KEYSTORE_PASSWORD` във файла `PCWork_Mobile_Release_v61_CREDENTIALS.txt`.
- `PCWORK_KEY_ALIAS` — `pcwork-release`.
- `PCWORK_KEY_PASSWORD` — стойността от `PCWORK_KEY_PASSWORD` във файла `PCWork_Mobile_Release_v61_CREDENTIALS.txt`.

Файловете с BASE64 и паролите се предоставят отделно от ZIP архива. Не ги добавяйте към GitHub repository.

## 2. Стартиране

След като добавите четирите secrets, отворете Actions → PCWork Android APK → Run workflow. Ако secrets липсват, workflow ще спре с ясно съобщение, вместо да подпише release APK с временен debug ключ.

## 3. Постоянни параметри

- Alias: `pcwork-release`
- Тип: JKS
- Валидност: 30 години
- Package ID: `com.pcworkbg.pcwork_mobile`
- Версия на приложението: `0.64.0+64`
- SHA-256 сертификат: `5C:05:0F:D1:31:FF:F7:2F:01:32:12:6B:F4:B2:07:88:83:29:01:5B:82:DF:88:69:BF:F1:ED:05:57:9F:45:AA`

За следващите версии използвайте същия `.jks` файл, пароли и alias. Не генерирайте нов ключ.


Ключът, създаден за v61, се използва повторно за v64 и всички следващи версии. Не генерирай нов ключ и не променяй паролите.
