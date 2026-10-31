/// Сервис локальной базы данных (SQLite).
///
/// Точка входа: на нативных платформах используется
/// реализация на `package:sqlite3`, на web — безопасная
/// заглушка (пакет sqlite3 не работает без dart:ffi).
library;

export 'database_service_io.dart'
    if (dart.library.js_interop) 'database_service_web.dart';
