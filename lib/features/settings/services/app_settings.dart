/// Хранилище настроек приложения.
///
/// Native — таблица `settings` в SQLite (схема была создана
/// заранее), web — `localStorage` (SQLite на web недоступен).
/// Обе реализации синхронны: значения маленькие и читаются
/// при инициализации провайдеров.
library;
export 'app_settings_io.dart'
    if (dart.library.js_interop) 'app_settings_web.dart';
