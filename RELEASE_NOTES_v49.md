# PCWork Mobile v49

## Промени
- Android GitHub Actions вече прочита Firebase client конфигурацията директно от `android/app/google-services.json`, проверява package name `com.pcworkbg.pcwork_mobile` и подава стойностите към Flutter чрез `--dart-define`. Не са необходими дублирани Android Firebase GitHub Secrets.
- Добавени са директни контакти на началния екран: телефон 0886638848, Viber, Facebook Messenger и TikTok.
- Премахната е Chaty интеграцията от мобилното приложение. Разделът за поддръжка запазва Chatway live chat.
- При избор на друга основна секция се затварят отворените диалози, долни панели и временни екрани; незаписаните чернови се изоставят.
- Обновена е версията до 0.49.0+49.

## Важно за Firebase
Реалният `android/app/google-services.json` трябва да присъства в GitHub checkout-а на проекта. Този архив умишлено не добавя реален Firebase конфигурационен файл или service-account ключ. Не качвайте service-account JSON в GitHub или в приложението.

## Остава за следваща стъпка
Корекцията на вертикалното позициониране на долната навигация е оставена извън тази версия, защото преди промяна поиска визуален преглед. Иконите няма да се смаляват; целта е да се намали празното пространство над тях и да се балансира отстоянието.

## Компилация
В GitHub отвори Actions → PCWork Android APK → Run workflow. При успешна компилация изтегли artifact `pcwork-android-v49-apks`.
