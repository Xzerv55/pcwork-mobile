# PCWork Mobile v32

**Версия:** `0.32.0+32` · Android / iOS · Български / English

## Ново във v32 – WooCommerce магазин
- Нов раздел **Магазин** в основната навигация.
- Реални публикувани продукти от WooCommerce със снимки, цени, кратко описание и наличност.
- Категории и търсене по име на продукт.
- Екран с подробности за продукта.
- Количка с управление на количествата.
- Поръчка за влезли клиенти с данни за контакт и адрес за доставка.
- Сървърна проверка на наличностите и създаване на реална WooCommerce поръчка.
- Изчисляване на доставка от конфигурираните WooCommerce зони; автоматично се избира най-евтиният наличен метод.
- Отваряне на стандартната WooCommerce страница за плащане, където се показват активните методи за плащане.
- История на поръчките за текущия профил.

## WordPress плъгин – задължителна актуализация
Във версията е включен единният плъгин **PCWork Mobile – Complete System 2.2.0** в:
`wordpress-plugin/pcwork-mobile-complete-system/`

Преди да използвате магазина:
1. Направете резервно копие на сайта.
2. Обновете единния PCWork Mobile плъгин до версия 2.2.0.
3. Уверете се, че WooCommerce е инсталиран и активен.
4. Отворете **PCWork Mobile → Интеграции** и включете WooCommerce.
5. В WooCommerce настройте зони/методи за доставка и поне един метод за плащане.
6. Проверете интеграцията с бутона „Провери връзката“.

**Consumer Key/Secret не се поставят в приложението.** Мобилният магазин използва WooCommerce PHP API на WordPress сървъра. Полетата за ключове остават само за външни REST API интеграции и не са задължителни за v32.

## Ограничения на първата версия на магазина
- Покупката е активна за прости (simple) WooCommerce продукти. Вариативните продукти се показват, но изборът на конкретна вариация ще бъде отделна функционалност.
- Количката се пази локално, докато екранът на магазина е активен; създадените поръчки се пазят в WooCommerce.
- За физически продукти трябва да има приложим метод за доставка за въведения адрес. Сървърът избира най-евтиния наличен метод от съответната зона.
- Плащането се довършва през защитената стандартна WooCommerce страница за плащане извън приложението.

## GitHub Actions
1. Качи съдържанието на `pcwork-mobile-main` в GitHub хранилището и замени старите файлове.
2. Отвори **Actions → PCWork Android APK**.
3. Изчакай `Analyze Dart code` и APK компилациите.
4. Изтегли артефакта `pcwork-android-v32-apks`.
5. За iOS стартирай **PCWork iOS unsigned build** и изтегли `pcwork-ios-v32-app-unsigned`.

Android workflow създава iOS asset catalog преди генерирането на launcher иконите, за да не се повтаря грешката с липсващия `AppIcon.appiconset`.

## Проверки
PHP синтаксисът на WooCommerce API и административните файлове е проверен локално с `php -l`. В тази среда няма Flutter SDK; `flutter analyze` и реалните Android/iOS компилации трябва да бъдат потвърдени чрез GitHub Actions.


## PCWork Mobile v33

Виж `V33_CHANGELOG_BG.md` за вариативни WooCommerce продукти, постоянна количка и подробности за поръчките.


## v34 – Login & Service Dashboard

The v34 release adds a dedicated sign-in/registration screen, email-or-username WordPress login, session restoration, password recovery link, and a signed-in home dashboard summary. Install the included WordPress plugin v2.4.1 before testing login. The app uses the existing WordPress account; no default username or password is created.

For login, use the email address or WordPress username and the existing account password. New customer registration creates a Subscriber account. Staff features remain restricted by WordPress roles and server-side permissions.
