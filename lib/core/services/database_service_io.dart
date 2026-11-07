import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';

import '../constants/app_constants.dart';


/// Реализация [DatabaseService] на нативных платформах
/// (Android / iOS / desktop) на базе `package:sqlite3`.
///
/// На web используется заглушка [DatabaseServiceWeb].

class DatabaseService {

  DatabaseService._();


  static final DatabaseService instance =
      DatabaseService._();


  /// Версия схемы базы данных.
  ///
  /// Хранится в `PRAGMA user_version`. При несовпадении версии таблицы
  /// контента (islands/pois/trails и связанные) пересоздаются заново —
  /// продовых данных контента в проекте ещё нет, мигрировать построчно
  /// не требуется. Таблицы `settings` и `favorites` при этом не удаляются.
  ///
  /// v3: pois.audio_ms/wave — длительность и огибающая аудио из
  /// poi.json (A8, 8-й проход).
  /// v4: trail_points.elevation — высоты точек трека из GPX/GeoJSON
  /// (A1, 16-й проход).

  static const int schemaVersion = 4;


  Database? _db;

  /// Идёт ли инициализация прямо сейчас (защита от параллельных
  /// вызовов: двойной тап «Повторить» не должен открывать два
  /// соединения — первое утекло бы).
  Future<void>? _initializing;

  bool get isOpen => _db != null;


  /// Открывает базу и применяет схему.
  ///
  /// [databaseDirectory] — каталог для базы (для тестов).
  /// По умолчанию используется каталог документов приложения.
  Future<void> initialize({
    String? databaseDirectory,
  }) async {

    if (isOpen) {
      return;
    }

    final inFlight = _initializing;

    if (inFlight != null) {
      return inFlight;
    }

    final future = _initializeAndCreateSchema(databaseDirectory);

    _initializing = future;

    try {
      await future;
    } finally {
      _initializing = null;
    }
  }


  Future<void> _initializeAndCreateSchema(
    String? databaseDirectory,
  ) async {

    final appDir = databaseDirectory != null
        ? Directory(databaseDirectory)
        : await getApplicationDocumentsDirectory();

    final dbDir = Directory(
      path.join(appDir.path, AppConstants.dbDirectory),
    );

    if (!await dbDir.exists()) {
      await dbDir.create(recursive: true);
    }

    final dbPath =
        path.join(dbDir.path, AppConstants.dbFileName);

    final db = sqlite3.open(dbPath);

    try {
      _createSchemaOn(db);
    } catch (_) {

      // Схема не применилась (диск, повреждение): соединение не
      // должно считаться открытым, иначе повторный initialize()
      // молча «преуспевал» и приложение работало с базой без
      // схемы. Закрываем и даём ошибке дойти до вызывающего.
      db.close();

      rethrow;
    }

    _db = db;
  }


  /// Закрывает базу.
  void close() {

    _db?.close();
    _db = null;
  }


  /// Выполняет SQL-запрос без результата.
  void execute(
    String sql, [
    List<Object?> parameters = const [],
  ]) {

    _requireDatabase().execute(
      sql,
      parameters,
    );
  }


  /// Пакетная вставка одним подготовленным выражением.
  ///
  /// SQL разбирается ОДИН раз, строки идут через prepared
  /// statement: сидинг крупного контента (сотни INSERT-ов)
  /// больше не парсит SQL на каждую строку (P1-7, 7-й проход).
  void insertBatch(
    String sql,
    Iterable<List<Object?>> rows,
  ) {
    final stmt = _requireDatabase().prepare(sql);

    try {
      for (final parameters in rows) {
        stmt.execute(parameters);
      }
    } finally {
      // dispose() у statement объявлен deprecated — close().
      stmt.close();
    }
  }


  /// Выполняет SELECT и возвращает строки
  /// в виде карт «имя колонки → значение».
  List<Map<String, Object?>> select(
    String sql, [
    List<Object?> parameters = const [],
  ]) {

    final result =
        _requireDatabase().select(
      sql,
      parameters,
    );

    return [
      for (var i = 0; i < result.length; i++)

        {
          for (var j = 0; j < result.columnNames.length; j++)

            result.columnNames[j]:
                result.rows[i][j],
        },
    ];
  }


  Database _requireDatabase() {

    final db = _db;

    if (db == null) {
      throw StateError(
        'База данных не инициализирована. Вызовите initialize()',
      );
    }

    return db;
  }


  /// Применяет схему к открытому соединению.
  ///
  /// Схема контента отслеживается через `PRAGMA user_version`: при
  /// несовпадении версии таблицы контента (и `history` из старой схемы)
  /// просто пересоздаются. Таблицы `settings` и `favorites` сохраняются.
  void _createSchemaOn(
    Database db,
  ) {

    // Внешние ключи в sqlite3 не включаются по умолчанию для каждого
    // нового соединения. Без этой прагмы `ON DELETE CASCADE` в схеме
    // молча не сработает. Прагма привязана к соединению, поэтому её
    // нужно ставить при каждом открытии, а не один раз глобально.
    db.execute('PRAGMA foreign_keys = ON;');

    if (db.userVersion != schemaVersion) {

      // Дочерние таблицы удаляются раньше родительских, чтобы не
      // наткнуться на ограничения внешних ключей при DROP.
      for (final table in const [
        'trail_images',
        'trail_points',
        'poi_trails',
        'poi_images',
        'trails',
        'pois',
        'islands',
        'history',
      ]) {
        db.execute('DROP TABLE IF EXISTS $table');
      }

      db.userVersion = schemaVersion;
    }

    db.execute(
      '''
      CREATE TABLE IF NOT EXISTS islands (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        language TEXT NOT NULL,
        country TEXT,
        stub INTEGER NOT NULL DEFAULT 0,
        map_asset TEXT,
        source_layer TEXT,
        map_center_lat REAL,
        map_center_lng REAL,
        map_bounds_west REAL,
        map_bounds_south REAL,
        map_bounds_east REAL,
        map_bounds_north REAL,
        island_bounds_west REAL,
        island_bounds_south REAL,
        island_bounds_east REAL,
        island_bounds_north REAL,
        content_version INTEGER NOT NULL,
        seeded_at INTEGER NOT NULL
      );
      ''',
    );

    db.execute(
      '''
      CREATE TABLE IF NOT EXISTS pois (
        id TEXT NOT NULL,
        island_id TEXT NOT NULL REFERENCES islands(id) ON DELETE CASCADE,
        title TEXT NOT NULL,
        latitude REAL NOT NULL,
        longitude REAL NOT NULL,
        radius REAL,
        description TEXT,
        audio_path TEXT,
        audio_ms INTEGER,
        wave TEXT,
        video_path TEXT,
        category TEXT,
        number INTEGER,
        sort_order INTEGER NOT NULL,
        PRIMARY KEY (island_id, id)
      );
      CREATE INDEX IF NOT EXISTS idx_pois_island ON pois(island_id);
      ''',
    );

    db.execute(
      '''
      CREATE TABLE IF NOT EXISTS poi_images (
        island_id TEXT NOT NULL,
        poi_id TEXT NOT NULL,
        path TEXT NOT NULL,
        sort_order INTEGER NOT NULL,
        FOREIGN KEY (island_id, poi_id) REFERENCES pois(island_id, id) ON DELETE CASCADE
      );
      CREATE INDEX IF NOT EXISTS idx_poi_images ON poi_images(island_id, poi_id);
      ''',
    );

    db.execute(
      '''
      CREATE TABLE IF NOT EXISTS poi_trails (
        island_id TEXT NOT NULL,
        poi_id TEXT NOT NULL,
        trail_id TEXT NOT NULL,
        FOREIGN KEY (island_id, poi_id) REFERENCES pois(island_id, id) ON DELETE CASCADE
      );
      CREATE INDEX IF NOT EXISTS idx_poi_trails_trail ON poi_trails(island_id, trail_id);
      CREATE INDEX IF NOT EXISTS idx_poi_trails_poi ON poi_trails(island_id, poi_id);
      ''',
    );

    db.execute(
      '''
      CREATE TABLE IF NOT EXISTS trails (
        id TEXT NOT NULL,
        island_id TEXT NOT NULL REFERENCES islands(id) ON DELETE CASCADE,
        name TEXT NOT NULL,
        description TEXT,
        distance REAL,
        PRIMARY KEY (island_id, id)
      );
      ''',
    );

    db.execute(
      '''
      CREATE TABLE IF NOT EXISTS trail_points (
        island_id TEXT NOT NULL,
        trail_id TEXT NOT NULL,
        line_index INTEGER NOT NULL,
        point_id TEXT NOT NULL,
        point_order INTEGER NOT NULL,
        latitude REAL NOT NULL,
        longitude REAL NOT NULL,
        elevation REAL,
        FOREIGN KEY (island_id, trail_id) REFERENCES trails(island_id, id) ON DELETE CASCADE
      );
      CREATE INDEX IF NOT EXISTS idx_trail_points ON trail_points(island_id, trail_id);
      ''',
    );

    db.execute(
      '''
      CREATE TABLE IF NOT EXISTS trail_images (
        island_id TEXT NOT NULL,
        trail_id TEXT NOT NULL,
        path TEXT NOT NULL,
        sort_order INTEGER NOT NULL,
        FOREIGN KEY (island_id, trail_id) REFERENCES trails(island_id, id) ON DELETE CASCADE
      );
      ''',
    );

    db.execute(
      '''
      CREATE TABLE IF NOT EXISTS settings (
        key TEXT PRIMARY KEY,
        value TEXT
      );
      ''',
    );

    db.execute(
      '''
      CREATE TABLE IF NOT EXISTS favorites (
        item_id TEXT PRIMARY KEY,
        created_at INTEGER NOT NULL
      );
      ''',
    );
  }
}