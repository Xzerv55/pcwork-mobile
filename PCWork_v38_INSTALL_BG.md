# PCWork Mobile v38 – инсталиране

## 1. WordPress интеграционен плъгин

1. Направете архив на сайта и базата данни преди обновяване.
2. В WordPress отворете **Plugins → Installed Plugins**.
3. Обновете съществуващия **PCWork Mobile – Complete System** с `PCWork_Mobile_WordPress_Plugin_v2.8.0.zip`. Не инсталирайте втори PCWork Mobile плъгин.
4. След активиране отворете **PCWork Mobile → Интеграции** и проверете текущите настройки. Запазените стойности се зареждат от същата WordPress опция `pcwork_mobile_integrations`; не изтривайте тази опция.
5. В секцията **Chaty** включете интеграцията и натиснете **Провери Chaty**. Официалният плъгин Chaty трябва да е активен и неговите скриптове да се зареждат на мобилната контактна страница.
6. Отворете **PCWork Mobile → Сервизни ремонти**. Там са списъкът, търсенето, филтрите, историята, документите и управлението на статуса/техника.

## 2. Android / iOS приложение

1. Разархивирайте `PCWork_Mobile_App_v38.zip`.
2. Качете съдържанието в GitHub хранилището `Xzerv55/pcwork-mobile`, като запазите папката `.github/workflows`.
3. В GitHub → **Actions** стартирайте **PCWork Android APK** или изчакайте автоматичното изпълнение след push.
4. Изчакайте `Analyze Dart code` и build стъпките да приключат успешно.
5. Отворете завършеното изпълнение → **Artifacts** → изтеглете `pcwork-android-v38-apks`.

За iOS стартирайте **PCWork iOS unsigned build**. Полученият артефакт е неподписан и изисква Apple signing преди реално разпространение.

## 3. Запазване на настройките

Плъгинът използва същата опция `pcwork_mobile_integrations` и същите ключове за Google Sheets, Bookly, Firebase, Chatway, Chaty и WooCommerce. Не деинсталирайте стария плъгин преди да потвърдите, че новият е активен и настройките са налични. Не въвеждайте повторно Google Sheets HMAC Secret или Apps Script URL, ако стойностите вече са запазени.

## 4. Важно

Тази доставка е проверена със статични проверки на PHP и целостта на ZIP архивите. Flutter SDK не е наличен в средата за създаване, затова `flutter analyze` и Android/iOS build трябва да бъдат потвърдени от GitHub Actions преди публикуване.


Забележка за Android/iOS: платформените native папки се генерират от Flutter в GitHub Actions чрез `scripts/prepare_android.sh` и `flutter create`. Те не са включени като готови native проекти в този ZIP.
