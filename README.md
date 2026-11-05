# PCWork Mobile v15

**Приложение:** 0.15.0+15  
**Единен WordPress плъгин:** PCWork Mobile – Complete System 1.7.0

В архива има само актуалният Flutter проект и единственият WordPress плъгин. Няма архиви на предишни версии или дублирани плъгини.

## Ново във v12 – клиентско табло

- Обобщение на ремонтите: всички, активни и готови.
- Търсене по номер на ремонт, устройство, модел, сериен номер и сервизен обект.
- Филтриране по статус.
- Визуална времева линия на етапите на ремонта.
- В клиентския изглед бележките от вътрешната история не се показват; служебните роли могат да ги виждат.
- Запазени са всички възможности от v11: прием на устройство, служебно табло, назначаване на техник, приоритети, срокове, протоколи, QR, документи, снимки и подписи.


## Ново във v13 – споделяне и по-удобна история на ремонтите

- Добавено е споделяне на кратка информация за ремонта чрез системното меню за споделяне на Android/iOS. Споделянето включва номер, устройство, статус, сервизен обект и краен срок, когато са налични; не включва вътрешни бележки, телефон или имейл.
- Добавено е копиране на номера на ремонта с едно натискане.
- Ремонтите се подреждат по дата на създаване – най-новите първо.
- В детайлите се показват крайният срок, приоритетът и назначеният техник според ролята. Приоритетът и името на техника са ограничени до служебните профили.
- Изборът на език и визуалният режим за преглед като служител се запазват локално между стартиранията. Визуалният режим не дава допълнителни права.

## Структура

- `lib/` – Flutter изходен код.
- `assets/` – PCWork лого и шрифтове с кирилица.
- `pubspec.yaml` – зависимости и версия.
- `wordpress-plugin/pcwork-mobile-complete-system.zip` – единственият WordPress плъгин.
- `.github/workflows/flutter-build.yml` – автоматично изграждане чрез GitHub Actions.

## Кога и къде се инсталира Flutter SDK?

Flutter SDK е безплатният инструментариум за компилиране на приложението. Той не се инсталира в WordPress и не е отделен модул в самото приложение.

В тази работна среда SDK не е наличен и няма достъп до интернет за изтеглянето му. За да не чакаме локална инсталация, добавих GitHub Actions workflow: при качване на проекта в GitHub и стартиране на workflow, GitHub runner автоматично изтегля стабилната версия на Flutter SDK, генерира платформените файлове и изпълнява `flutter pub get` и `flutter analyze`.

### Android

Workflow-ът изгражда release APK и го публикува като artifact `pcwork-android-apk`. Необходимо е проектът да бъде качен в GitHub repository и workflow-ът да бъде стартиран от Actions.

### iOS

Workflow-ът използва macOS runner и изгражда неподписано iOS приложение (`Runner.app`). За реален IPA за iPhone разпространение са нужни Apple Developer signing сертификати/provisioning profile и конфигуриране на signing secrets. Това не може да бъде заместено само с Flutter SDK.

## Локално изграждане

След инсталиране на Flutter stable SDK:

```bash
flutter create --platforms=android,ios .
flutter pub get
flutter analyze
flutter build apk --release
```

За iOS се използва macOS с Xcode:

```bash
flutter build ios --release --no-codesign
```

## WordPress плъгин

1. Направете резервно копие на WordPress файловете и базата данни.
2. Ако са активни старите три PCWork плъгина, деактивирайте ги, но не ги изтривайте преди тест.
3. Качете `wordpress-plugin/pcwork-mobile-complete-system.zip` от Разширения → Добавяне на нов → Качване на разширение.
4. Активирайте **PCWork Mobile – Complete System**.
5. Проверете настройките в **PCWork Mobile → Интеграции** и правата/локациите на служителите.
6. Извършете тестове в staging среда преди production.

## Проверки и ограничения

- Архивите се проверяват с `unzip -t`.
- PHP файловете на единния плъгин трябва да преминат `php -l` при локална проверка.
- В тази среда няма Flutter SDK и не е изпълнен `flutter analyze`; APK/IPA не са компилирани тук.
- GitHub Actions workflow-ът е добавен, но не е изпълнен оттук и резултатният build не е проверен.
- Реални интеграционни тестове със сайта, Google Sheets, SMTP и Firebase са необходими преди production.
- За iOS IPA е необходимо Apple signing. За Android подписан APK/AAB за Play Store е необходимо конфигуриране на release keystore.


## Ново във v14 – push известия за Android и iOS

- Добавена е интеграция с Firebase Cloud Messaging (FCM) чрез `firebase_core` и `firebase_messaging`.
- След вход приложението иска разрешение за известия, получава FCM registration token и го регистрира в WordPress с Bearer токена на профила.
- Поддържа се автоматично обновяване и повторна регистрация на FCM token.
- При известие, докато приложението е отворено, се показва съобщение в приложението и се обновява списъкът с ремонти.
- При натискане на push известие приложението отваря раздел „Ремонти“.
- При изход устройството се отписва от push известията за текущия профил.
- WordPress push endpoints вече използват същата Bearer авторизация като мобилния API. Това поправя несъвместимостта между custom JWT входа на приложението и проверката `is_user_logged_in()`.
- WordPress плъгинът е актуализиран до 1.7.0; FCM изпращането през Firebase HTTP v1 и сервизния акаунт остава от сървърната страна.

### Необходими Firebase настройки

1. Създай/използвай Firebase проект и добави Android приложение със същия application ID, който ще използва PCWork.
2. Добави iOS приложение със същия Bundle ID за iOS build.
3. В GitHub repository → Settings → Secrets and variables → Actions добави:
   - `FIREBASE_PROJECT_ID`
   - `FIREBASE_MESSAGING_SENDER_ID`
   - `FIREBASE_ANDROID_API_KEY`
   - `FIREBASE_ANDROID_APP_ID`
   - `FIREBASE_IOS_API_KEY`
   - `FIREBASE_IOS_APP_ID`
   - `FIREBASE_IOS_BUNDLE_ID`
4. В WordPress → PCWork Mobile → Интеграции включи Push известията и въведи Firebase Project ID и пълния Firebase Service Account JSON. Сервизният акаунт е само за WordPress сървъра; никога не го поставяй в мобилното приложение или GitHub `dart-define` secrets.
5. Запази настройките и използвай тестовото FCM устройство, за да провериш връзката.
6. За iOS активирай Push Notifications capability и настрой APNs authentication key/certificate във Firebase Console. Без APNs конфигурация iOS няма да получава реални push известия.

### Поведение без конфигуриран Firebase

Приложението продължава да работи и без Firebase конфигурация. Push модулът се пропуска, без да блокира входа или останалите функции. За реални известия трябва да бъдат въведени Firebase client app параметрите в GitHub Actions и сървърният Service Account JSON в WordPress.

### Проверки и ограничения във v14

- Не е изпълнен `flutter pub get`, `flutter analyze` или реален Android/iOS build в тази среда, тъй като Flutter SDK и интернет достъпът липсват.
- Не са извършени live тестове с Firebase, APNs или production WordPress сайт.
- За iOS push са нужни валидни APNs настройки; за Android устройството трябва да има съвместими Google Play services.
- Push известията за промяна на статус се изпращат от WordPress само след конфигуриране на Firebase и активиране на push интеграцията.


## Ново във v15 – подготовка за Android APK

- Версията на Flutter приложението е `0.15.0+15`.
- Добавен е Android build workflow `PCWork Android APK`, който се стартира ръчно от GitHub Actions или автоматично при push към `main`/`master`.
- Добавен е скрипт `scripts/prepare_android.sh`, който генерира Android host проекта с application ID `com.pcworkbg.pcwork_mobile`, име `PCWork` и минимален Android API 23.
- Workflow-ът изпълнява `flutter pub get`, `flutter analyze` и създава `app-debug.apk` за инсталиране/тестване и `app-release.apk` за допълнителни device тестове. Двата файла се публикуват като artifact `pcwork-android-v15-apks`.
- Подробните стъпки за GitHub, изтегляне и инсталиране са в `ANDROID_APK_GUIDE_BG.md`.
- iOS unsigned workflow-ът е отделен и се стартира ръчно, за да не дублира Android build при всеки push.

### Важна граница на изпълнението

В тази работна среда няма Flutter SDK и интернет/DNS достъп за изтеглянето му. Затова v15 подготвя възпроизводим Android build в GitHub Actions, но **APK файл още не е компилиран или тестван на телефон**. Реалният build ще се изпълни в GitHub runner след качване на проекта и стартиране на workflow-а. Зелен резултат в Actions и инсталация на физическо устройство са нужни, преди да отчетем APK като успешно изграден и проверен.

`app-debug.apk` е за вътрешно тестване. За Google Play/production release е необходимо отделно управление на release keystore и подписване; не качвайте private keystore или Firebase Service Account JSON в source кода.
