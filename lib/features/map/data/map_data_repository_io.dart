import '../../../core/services/database_service.dart';
import '../../../core/utils/logger.dart';
import '../../content/models/region_catalog.dart';
import '../../content/services/content_seeder.dart';
import '../../content/services/markdown_blocks.dart';
import '../../content/services/poi_text_loader.dart';
import '../../poi/models/poi.dart';
import '../../trails/models/trail.dart';
import '../../trails/models/trail_point.dart';


/// Репозиторий данных карты на нативных платформах.
///
/// Читает POI и маршруты из SQLite. База наполняется лениво
/// через [ContentSeeder.ensureSeeded] при первом обращении
/// к острову (или при смене `content_version` в манифесте).

final class MapDataRepository {

  const MapDataRepository({
    required this.islandId,
  });


  /// Идентификатор локации (пакета в `content/<region>/<location>/`).
  final String islandId;


  String get _basePath =>
      locationAssetBase(islandId);


  Future<List<Poi>> loadPois() async {

    AppLogger.info('[MapDataRepository] loadPois island=$islandId');

    await ContentSeeder.instance.ensureSeeded(islandId);

    final db = DatabaseService.instance;

    final rows = db.select(
      '''
      SELECT * FROM pois
      WHERE island_id = ?
      ORDER BY (number IS NULL), number, sort_order
      ''',
      [islandId],
    );

    // Связанные данные грузим одним запросом на таблицу (без N+1).
    final images =
        _loadImagesFor(db, islandId);

    final trailIds =
        _loadTrailIdsFor(db, islandId);

    final pois = rows.map((r) {

      final id = r['id'] as String;

      return Poi(
        id: id,
        title: r['title'] as String,
        latitude: r['latitude'] as double,
        longitude: r['longitude'] as double,
        radius: r['radius'] as double?,
        description: r['description'] as String?,
        audioPath: r['audio_path'] as String?,
        audioMs: r['audio_ms'] as int?,
        wave: r['wave'] as String?,
        videoPath: r['video_path'] as String?,
        imagePaths: images[id] ?? const [],
        trailIds: trailIds[id] ?? const [],
        category: r['category'] as String?,
        number: r['number'] as int?,
      );
    }).toList();

    AppLogger.info('[MapDataRepository] loadPois island=$islandId -> ${pois.length}');

    return pois;
  }


  Future<List<Trail>> loadTrails() async {

    AppLogger.info('[MapDataRepository] loadTrails island=$islandId');

    await ContentSeeder.instance.ensureSeeded(islandId);

    final db = DatabaseService.instance;

    final rows = db.select(
      'SELECT * FROM trails WHERE island_id = ?',
      [islandId],
    );

    final pointRows = db.select(
      '''
      SELECT * FROM trail_points
      WHERE island_id = ?
      ORDER BY line_index, point_order
      ''',
      [islandId],
    );

    final imageRows = db.select(
      '''
      SELECT * FROM trail_images
      WHERE island_id = ?
      ORDER BY sort_order
      ''',
      [islandId],
    );

    // Группируем точки по маршруту и ветке (line_index) в один проход.
    final linesByTrail = <String, List<List<TrailPoint>>>{};

    for (final row in pointRows) {

      final trailId = row['trail_id'] as String;

      final lines = linesByTrail.putIfAbsent(trailId, () => []);

      final lineIndex = row['line_index'] as int;

      while (lines.length <= lineIndex) {
        lines.add([]);
      }

      // Высота (A1): колонка есть со схемы v4; старые базы
      // пересеиваются (схема не совпала → дроп и новый сидинг).
      final elevation = row['elevation'];

      lines[lineIndex].add(
        TrailPoint(
          id: row['point_id'] as String,
          latitude: row['latitude'] as double,
          longitude: row['longitude'] as double,
          order: row['point_order'] as int,
          elevation: elevation is double ? elevation : null,
        ),
      );
    }

    final imagesByTrail = <String, List<String>>{};

    for (final row in imageRows) {

      imagesByTrail
          .putIfAbsent(row['trail_id'] as String, () => [])
          .add(row['path'] as String);
    }

    final trails = rows.map((r) {

      final trailId = r['id'] as String;

      final lines = linesByTrail[trailId] ?? const [];

      final List<List<TrailPoint>> effectiveLines;

      final List<TrailPoint> points;

      if (lines.length > 1) {
        effectiveLines = lines;
        points = lines.expand((line) => line).toList();
      } else {
        effectiveLines = const [];
        points = lines.isEmpty ? const [] : lines.first;
      }

      return Trail(
        id: trailId,
        name: r['name'] as String,
        description: r['description'] as String?,
        distance: r['distance'] as double?,
        points: points,
        lines: effectiveLines.isEmpty ? null : effectiveLines,
        imagePaths: imagesByTrail[trailId] ?? const [],
      );
    }).toList();

    // Ленивый лог: map/toList по всем маршрутам — только в debug.
    AppLogger.infoFn(
      () => '[MapDataRepository] loadTrails island=$islandId -> '
          '${trails.map((t) => t.name).toList()}',
    );

    return trails;
  }


  /// Грузит изображения POI острова: `poi_id` → список путей
  /// в порядке из `poi.json`.
  Map<String, List<String>> _loadImagesFor(
    DatabaseService db,
    String islandId,
  ) {

    final rows = db.select(
      '''
      SELECT poi_id, path FROM poi_images
      WHERE island_id = ?
      ORDER BY sort_order
      ''',
      [islandId],
    );

    final result = <String, List<String>>{};

    for (final row in rows) {

      result
          .putIfAbsent(row['poi_id'] as String, () => [])
          .add(row['path'] as String);
    }

    return result;
  }


  /// Грузит id маршрутов POI острова: `poi_id` → список id
  /// в порядке из `poi.json` (порядок вставки = rowid).
  Map<String, List<String>> _loadTrailIdsFor(
    DatabaseService db,
    String islandId,
  ) {

    final rows = db.select(
      '''
      SELECT poi_id, trail_id FROM poi_trails
      WHERE island_id = ?
      ORDER BY rowid
      ''',
      [islandId],
    );

    final result = <String, List<String>>{};

    for (final row in rows) {

      result
          .putIfAbsent(row['poi_id'] as String, () => [])
          .add(row['trail_id'] as String);
    }

    return result;
  }


  /// Полный текст POI СТРУКТУРОЙ блоков markdown (B3.4).
  ///
  /// [folderNumber] — номер файла в папке `text/` (нумерация как
  /// на карте). Файл ищется по префиксу `NN - ` среди ассетов
  /// острова. Возвращает `null`, если файл не найден.
  ///
  /// Полные тексты намеренно не дублируются в SQLite — это большие
  /// markdown-файлы, не участвующие в сортировке/фильтрации.
  /// Поиск файла и вырезание заголовка — в [PoiTextLoader]
  /// (общий код для io и web).
  Future<List<MdBlock>?> loadPoiFullBlocks(int folderNumber) async {
    return PoiTextLoader.loadFullBlocks(
      _basePath,
      islandId,
      folderNumber,
    );
  }

  /// Полный текст достопримечательности из `text/NN - Title.md`
  /// (сырой markdown).
  ///
  /// [folderNumber] — номер файла в папке `text/` (нумерация как
  /// на карте). Файл ищется по префиксу `NN - ` среди ассетов
  /// острова. Возвращает `null`, если файл не найден.
  ///
  /// Полные тексты намеренно не дублируются в SQLite — это большие
  /// markdown-файлы, не участвующие в сортировке/фильтрации.
  /// Поиск файла и вырезание заголовка — в [PoiTextLoader]
  /// (общий код для io и web).
  Future<String?> loadPoiFullText(int folderNumber) async {

    return PoiTextLoader.loadFullText(
      _basePath,
      islandId,
      folderNumber,
    );
  }
}