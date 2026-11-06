# PCWork Mobile v30

**Версия:** `0.30.0+30`  
**Платформи:** Android и iOS  
**Език:** Български / English  
**Основен API:** `https://pcwork-bg.com`

## Какво е новото във v30
- Оригиналното PCWork 3D лого вече е икона на самото приложение (Android/iOS).
- Android adaptive launcher icon с графитен фон и оригиналния знак.
- Native стартов екран (splash screen) с PCWork логото.
- Логото в горната лента е с правилно пропорционално показване, без изрязване.
- Запазени са Chatway интеграцията, клиентската/служителската функционалност и тъмната PCWork визия.

## GitHub компилация
1. Качи съдържанието на `pcwork-mobile-main` в GitHub хранилището и замени старите файлове.
2. Отвори **Actions → PCWork Android APK**.
3. Изчакай стъпките `flutter analyze` и `Build ... APK`.
4. Изтегли `pcwork-android-v30-apks`.
5. За iOS стартирай ръчно workflow **PCWork iOS unsigned build** и изтегли `pcwork-ios-v30-app-unsigned`.

Workflow-ите автоматично генерират launcher и splash ресурсите след `flutter pub get`.

## Chatway
Chatway остава конфигуриран през WordPress: **PCWork Mobile → Интеграции → Chatway**. Не поставяй Visitor Verification Security Key в Flutter кода или GitHub.

## Важно
В тази среда няма инсталиран Flutter SDK. YAML файловете са проверени за синтаксис, но `flutter analyze` и реалните Android/iOS компилации трябва да се потвърдят от GitHub Actions. За iOS инсталация върху устройство е необходима и подписана компилация с Apple Developer профил.
