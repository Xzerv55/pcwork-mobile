# PCWork Mobile v50 – инструкции за обновяване

1. Направи резервно копие на GitHub проекта и WordPress сайта/базата данни.
2. Замени файловете на Flutter проекта с тези от папка `New folder` в архива. При качване през GitHub уеб интерфейса изтрий стария файл `lib/screens/chaty_screen.dart`, ако все още съществува в хранилището.
3. Провери, че няма останали импорти или извиквания на `getChatyUrl()` в `lib/`. Във версията v50 такива извиквания няма.
4. Запази реалния `android/app/google-services.json` в проекта. Той умишлено не е включен в ZIP архива. Не качвай Service Account JSON или частни ключове в GitHub.
5. В GitHub Actions стартирай `PCWork Android APK` чрез `Run workflow`. Провери логовете на стъпката за Firebase конфигурация и изтегли APK artifact-а след успешен build.
6. За WordPress обнови съществуващия плъгин `PCWork Mobile – Complete System` с файловете от `wordpress-plugin/pcwork-mobile-complete-system/`. Не инсталирай второ копие.
7. След обновяването отвори PCWork Mobile → Интеграции и провери останалите настройки. Chaty вече няма да присъства там; директните контактни бутони в приложението остават.

**Важно:** Премахването на Chaty от PCWork плъгина не деактивира отделния външен Chaty плъгин в WordPress. Ако искаш той да не показва балон/бутони и на сайта, деактивирай го отделно от Plugins → Installed Plugins.
