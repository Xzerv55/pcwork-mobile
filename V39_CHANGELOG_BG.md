# PCWork Mobile v39 – промени

## Финална интеграция и оптимизация
- Версия на приложението: `0.39.0+39`.
- Единен WordPress плъгин: `2.9.0` (надграждане върху 2.8.0, без изтриване на текущите настройки).
- Добавен екран „Статистика и отчети“ в служебното табло: общ брой ремонти, ремонти в процес, просрочени ремонти, чакащи офлайн синхронизация, разбивка по статус, сервизен обект и техник.
- Запазени са ремонтите, историята, протоколите, документите, разпределението към техник, Chaty/Chatway, Firebase Messaging, офлайн опашката и двуезичният интерфейс.
- Добавени са Android и iOS platform scaffolds в архива. Android workflow генерира пълния native host от Flutter SDK и запазва реалния `android/app/google-services.json`, ако е добавен.
- Android package / iOS bundle ID: `com.pcworkbg.pcwork_mobile`.
- Firebase JSON примерът е само шаблон; той не е валиден конфигурационен файл. Използвайте изтегления от Firebase Console файл.

## Важно за push известията
Android: поставете Firebase файла на `android/app/google-services.json`. iOS: конфигурирайте APNs във Firebase и добавете необходимите build-time Firebase стойности в GitHub Actions secrets. Самото добавяне на Android JSON не активира APNs.

## Проверки
Архивът е проверен за ZIP целостта и структурата. В тази среда няма Flutter/Dart SDK и не е изпълнен `flutter analyze`, Android Gradle build или Xcode build. Тези проверки трябва да се изпълнят от GitHub Actions; не се твърди предварително успешна компилация.
