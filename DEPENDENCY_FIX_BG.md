# Корекция на Font Awesome за Flutter

- `font_awesome_flutter` е фиксиран на версия `11.0.0`, която вече не наследява `IconData` и е съвместима с промяната във Flutter, при която `IconData` е `final`.
- Единственото използване на Font Awesome в приложението (TikTok) е преминало към `FaIcon`.
- Общата карта за контакт приема готов `Widget`, така че Material и Font Awesome иконите да се показват със същия размер и цвят.

След разархивиране изпълнете `flutter pub get`. Flutter ще създаде `pubspec.lock` в основната папка на проекта. След това стартирайте GitHub Actions build.

Бележка: В тази среда няма Flutter/Dart SDK, затова `pubspec.lock` не е генериран и не е изпълняван реален Flutter build.
