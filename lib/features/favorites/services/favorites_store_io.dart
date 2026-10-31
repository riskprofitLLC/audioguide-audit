import '../../../core/services/database_service.dart';


/// Хранилище избранного на нативных платформах.
///
/// Сохраняет выбранные объекты (POI и маршруты)
/// в таблицу `favorites` локальной базы SQLite.
///
/// Если база не инициализирована (например, в тестах
/// без седера), операции безопасно возвращают пустое
/// множество / no-op.

final class FavoritesStore {

  FavoritesStore({
    DatabaseService? database,
  }) : _db = database ?? DatabaseService.instance;


  final DatabaseService _db;


  /// Загружает id избранных объектов.
  Future<Set<String>> loadFavoriteIds() async {

    if (!_db.isOpen) {
      return const {};
    }

    final rows = _db.select(
      'SELECT item_id FROM favorites ORDER BY created_at DESC',
    );

    return {
      for (final row in rows)
        row['item_id'] as String,
    };
  }


  /// Добавляет объект в избранное.
  Future<void> addFavorite(
    String itemId,
  ) async {

    if (!_db.isOpen) {
      return;
    }

    _db.execute(
      '''
      INSERT OR REPLACE INTO favorites (item_id, created_at)
      VALUES (?, ?)
      ''',
      [
        itemId,
        DateTime.now().millisecondsSinceEpoch,
      ],
    );
  }


  /// Добавляет несколько объектов одним запросом (каскад маршрута:
  /// маршрут + все его POI пишутся одной операцией, а не N-ем
  /// круглых путей к БД).
  Future<void> addFavorites(
    Iterable<String> itemIds,
  ) async {

    final ids = itemIds.toList();

    if (ids.isEmpty || !_db.isOpen) {
      return;
    }

    final now = DateTime.now().millisecondsSinceEpoch;

    final values = List.filled(ids.length, '(?, ?)').join(', ');

    _db.execute(
      '''
      INSERT OR REPLACE INTO favorites (item_id, created_at)
      VALUES $values
      ''',
      [
        for (final id in ids) ...[id, now],
      ],
    );
  }


  /// Убирает объект из избранного.
  Future<void> removeFavorite(
    String itemId,
  ) async {

    if (!_db.isOpen) {
      return;
    }

    _db.execute(
      'DELETE FROM favorites WHERE item_id = ?',
      [itemId],
    );
  }


  /// Убирает несколько объектов из избранного одним запросом.
  ///
  /// Для чистки устаревших ключей (локации, удалённые из каталога).
  Future<void> removeFavorites(
    Iterable<String> itemIds,
  ) async {

    final ids = itemIds.toList();

    if (ids.isEmpty || !_db.isOpen) {
      return;
    }

    final placeholders = List.filled(ids.length, '?').join(', ');

    _db.execute(
      'DELETE FROM favorites WHERE item_id IN ($placeholders)',
      ids,
    );
  }


  /// Удаляет все избранное.
  Future<void> clearAll() async {

    if (!_db.isOpen) {
      return;
    }

    _db.execute('DELETE FROM favorites');
  }
}
