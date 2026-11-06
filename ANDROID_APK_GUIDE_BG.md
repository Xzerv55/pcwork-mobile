# PCWork v38 – получаване и инсталиране на Android APK

- Версия на приложението: `0.38.0+38`.
- Източник: GitHub `Xzerv55/pcwork-mobile`.
- Workflow: **PCWork Android APK**.

## Стъпки
1. Разархивирайте `PCWork_Mobile_App_v38.zip`.
2. Качете всички файлове в GitHub хранилището, като запазите `.github/workflows`.
3. Отворете GitHub → Actions → **PCWork Android APK**.
4. Изчакайте `Analyze Dart code`, debug APK и release APK да приключат успешно.
5. Отворете изпълнението → Artifacts → `pcwork-android-v38-apks`.
6. Изтеглете архива и инсталирайте `app-release.apk` на Android устройството. Ако Android блокира инсталацията, разрешете инсталиране от този източник.

Ако `flutter analyze` покаже грешка, изпратете пълния лог. Не продължавайте към публикуване, докато анализът и build стъпките не са зелени.
