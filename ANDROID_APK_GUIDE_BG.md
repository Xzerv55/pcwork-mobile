# PCWork v37 – получаване и инсталиране на Android APK

## Какво е подготвено

- Версия на приложението: `0.37.0+37`.
- Android application ID: `com.pcworkbg.pcwork_mobile`.
- Име на приложението на телефона: `PCWork`.
- Минимална Android версия/API: 23 (Android 6.0).
- GitHub Actions workflow: `.github/workflows/android-apk.yml`.
- Скрипт за генериране на Android host проекта: `scripts/prepare_android.sh`.

Workflow-ът генерира два APK файла: `app-debug.apk` за първоначално тестване и `app-release.apk` за допълнително тестване на release конфигурацията. Release APK в този етап не е подписан с личен production keystore; не го използвайте за Google Play публикуване.

## Стъпки за получаване на APK

1. Отворете съществуващото repository `Xzerv55/pcwork-mobile`.
2. Разархивирайте `PCWork_Mobile_App_v37.zip` на компютъра.
3. Качете съдържанието на разархивирания проект в основната директория на repository-то. Качва се съдържанието, а не самият ZIP файл.
4. В GitHub отворете **Actions**. Ако GitHub поиска разрешение за workflows, изберете разрешаване.
5. От списъка изберете **PCWork Android APK**.
6. Натиснете **Run workflow** → **Run workflow**.
7. Изчакайте задачата да приключи със зелена отметка. Отворете изпълнението и в секцията **Artifacts** изтеглете `pcwork-android-v37-apks`.
8. Разархивирайте artifact ZIP файла. За обичайно първоначално тестване използвайте `app-debug.apk`.

При всяко качване към `main` или `master` workflow-ът се стартира автоматично.

## Инсталиране на телефона

1. Прехвърлете `app-debug.apk` на Android телефона.
2. Отворете APK файла от Downloads/Файлове.
3. Ако Android поиска, разрешете **Install unknown apps / Инсталиране на неизвестни приложения** за приложението, с което отваряте файла.
4. Потвърдете инсталацията и стартирайте **PCWork**.
5. Проверете началния екран, връзката със `https://pcwork-bg.com`, входа, клиентското табло и служебния профил.

Ако вече има инсталирана версия със същия application ID, Android може да откаже обновяване, ако подписът е различен. В тестова среда деинсталирайте старата версия и инсталирайте новия APK. Това може да изтрие локалните данни на приложението.

## Firebase Push – незадължително за първия APK

Приложението може да се стартира без Firebase client настройки, но реалните push известия няма да работят. За тях добавете в GitHub → Settings → Secrets and variables → Actions:

- `FIREBASE_PROJECT_ID`
- `FIREBASE_MESSAGING_SENDER_ID`
- `FIREBASE_ANDROID_API_KEY`
- `FIREBASE_ANDROID_APP_ID`

Във Firebase регистрирайте Android app с точно този package name:

`com.pcworkbg.pcwork_mobile`

На WordPress сървъра Service Account JSON остава само в настройките на PCWork Mobile плъгина. Не го качвайте в GitHub и не го включвайте в APK.

## Какво не е production-ready

- APK-ът от този workflow е за вътрешно тестване, не за Google Play публикуване.
- За production release трябва да се създаде и пази Android upload/release keystore, да се конфигурира signing през GitHub Secrets и да се генерира подписан APK/AAB.
- Не е включен реален Firebase project или лични ключове.
- Успешният APK build и тестовете на физически телефон се потвърждават едва след изпълнение на workflow-а и инсталиране.
