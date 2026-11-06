# PCWork Mobile v30 – фирмена идентичност в самото приложение

## Основно обновяване
- Версия на приложението: `0.30.0+30`.
- Оригиналното PCWork 3D лого е включено като launcher icon за Android и iOS.
- Добавена е Android adaptive icon конфигурация с тъмен графитен фон и оригиналното лого като foreground.
- Добавен е native splash screen с оригиналното лого върху фон `#0A101A`.
- Логото в горната лента е коригирано да се показва с `BoxFit.contain`, без изрязване.
- Запазена е досегашната тъмна PCWork тема с цианови и виолетови акценти.

## Автоматично генериране
GitHub Actions генерира иконите и splash ресурсите след `flutter pub get` чрез. Android workflow предварително създава и iOS asset catalog, защото `flutter_launcher_icons` е конфигуриран за Android и iOS; това предотвратява липсващия `AppIcon.appiconset` при генериране:
- `dart run flutter_launcher_icons`
- `dart run flutter_native_splash:create`

## Chatway и WordPress
Запазена е Chatway интеграцията от v29 и WordPress плъгинът v2.1.0. В тази версия няма промяна на WordPress API договорите.

## Проверки
Flutter SDK не е наличен в средата за създаване на архива. Затова `flutter analyze` и Android/iOS компилациите трябва да се потвърдят чрез GitHub Actions. Workflow-ите са обновени с генериране на иконите/splash и нови имена на артефактите.
