# PCWork Mobile v42 — поправка на Flutter analyze

- Поправен е callback-ът за отваряне на push известие. `onMessageOpenedApp` вече подава `message.data` към `onOpened`, както изисква callback сигнатурата.
- Версия на приложението: `0.42.0+42`.
- WordPress плъгинът остава съвместим с версия 3.1.0 и не изисква обновяване за тази поправка.
