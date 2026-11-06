# PCWork v53 – инструкции за обновяване

1. Направи резервно копие на WordPress сайта и текущите Apps Script файлове.
2. Обнови WordPress плъгина от `wordpress-plugin/pcwork-mobile-complete-system/`. Деактивирай стария ZIP само ако WordPress не позволява директно презаписване; не изтривай базата данни или настройките.
3. В Google Apps Script замени съдържанието на `Code.gs` с файла `google-apps-script/Code.gs`. Запази съществуващите Script Properties: `PCWORK_HMAC_SECRET`, `PCWORK_SPREADSHEET_ID`, `PCWORK_SHEET_NAME=Repairs`.
4. Избери Deploy → Manage deployments → Edit → New version → Deploy. Използвай същия `/exec` адрес. Настройки: Execute as Me; Who has access Anyone.
5. В WordPress провери, че Google Sheets интеграцията е включена и URL/ HMAC secret съвпадат със Script Properties. Не променяй secret-а.
6. Създай тестов ремонт и провери листа `Repairs`. При редакция на статус, техник, приоритет или срок същият Repair ID трябва да се обнови, а не да се дублира.
7. За FCM постави целия оригинален Service Account JSON в настройката, без да редактираш `private_key`. Не изпращай JSON или private key по чат. След това изпрати тестово известие.
8. За Android APK използвай GitHub Actions workflow от този архив.

Ако Apps Script върне грешка, отвори Executions и изпрати само съобщението за грешка/request ID – без ключове и токени.
