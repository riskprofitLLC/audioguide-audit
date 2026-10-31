/// Репозиторий данных карты.
///
/// Точка входа: на нативных платформах читает POI и маршруты из SQLite
/// (`map_data_repository_io.dart`), на web — напрямую из ассетов
/// (`map_data_repository_web.dart`), как и раньше.
library;

export 'map_data_repository_io.dart'
    if (dart.library.js_interop) 'map_data_repository_web.dart';