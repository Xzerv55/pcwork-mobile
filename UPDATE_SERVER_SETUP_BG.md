# Настройка на актуализациите от pcwork-bg.com

1. Създай папка `wp-content/uploads/pcwork-mobile/` на хостинга.
2. Качи подписания APK с име `PCWork-Mobile.apk`.
3. Изчисли SHA-256 на APK файла (на Windows PowerShell: `Get-FileHash .\PCWork-Mobile.apk -Algorithm SHA256`).
4. Качи `update.json` в същата папка. Използвай `update.json.example` като шаблон и замени стойностите:
   - `version`: версията от `pubspec.yaml` (например `0.67.0`)
   - `version_code`: Android build number (например `67`)
   - `apk_url`: HTTPS адресът на APK файла на `pcwork-bg.com`
   - `sha256`: 64-символната SHA-256 стойност от предишната стъпка
   - `release_notes`: кратко описание
   - `mandatory`: `false` за незадължителна актуализация
5. Приложението проверява манифеста през `https://pcwork-bg.com/wp-json/pcwork/v1/app/update`. WordPress плъгинът прочита локалния файл `wp-content/uploads/pcwork-mobile/update.json`.

Важно: APK трябва да е подписан със същия постоянен release ключ като предишните версии и със същия Android package ID. Android показва системния инсталатор и изисква потвърждение от потребителя. Ако поиска разрешение за инсталиране от PCWork, разреши го в системните настройки и натисни отново „Актуализирай сега“.
