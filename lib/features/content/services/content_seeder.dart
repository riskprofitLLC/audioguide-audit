import 'dart:async';

import 'package:flutter/services.dart';

import '../../../core/services/database_service.dart';
import '../../../core/utils/logger.dart';
import '../../poi/models/poi.dart';
import '../../poi/services/poi_json_parser.dart';
import '../../trails/models/trail.dart';
import '../models/manifest.dart';
import '../models/region_catalog.dart';
import 'content_loader.dart';
import 'geojson_trails_parser.dart';
import 'gpx_trails_parser.dart';


/// Сидер офлайн-контента.
///
/// Лениво импортирует пакет острова (`content/<island_id>/`) в SQLite
/// при первом обращении к острову. Повторный сидинг пропускается,
/// если `content_version` в БД совпадает с версией из `manifest.json`;
/// при смене версии старые строки острова удаляются (каскадом) и
/// вставляются новые.

final class ContentSeeder {

  ContentSeeder._();


  static final ContentSeeder instance =
      ContentSeeder._();


  /// Незавершённые сидинги по островам.
  ///
  /// Нужен, чтобы конкурентные обращения к одному острову (например,
  /// `poisProvider` и `trailsProvider` в одном кадре) ждали один и тот же
  /// результат, а не выполняли сидинг параллельно — иначе возможен
  /// интерлив `DELETE`/`INSERT` и задвоение строк в связанных таблицах
  /// без собственного PK (`poi_images`, `trail_points`, ...).
  final Map<String, Future<void>> _inFlight = {};

  /// Хвост глобальной очереди сидингов.
  ///
  /// Сидинг внутри себя держит транзакцию SQLite с `await` (чтение
  /// ассетов), а перекрывать транзакции на одном соединении нельзя.
  /// Поэтому сидинги РАЗНЫХ островов (их параллельно запускают
  /// потребители карты «все регионы» через `Future.wait`) нанизываются
  /// на единую очередь: каждый следующий начинается только после
  /// завершения предыдущего. Ошибки одного сидинга не отравляют
  /// очередь.
  Future<void> _globalTail = Future<void>.value();


  /// Гарантирует, что контент острова есть в БД и актуален.
  Future<void> ensureSeeded(String islandId) {

    final operation = _globalTail.then((_) {
      return _inFlight.putIfAbsent(
        islandId,
        () async {
          try {
            await _ensureSeededInternal(islandId);
          } finally {
            // Возврат Future из remove() намеренно не ждём — только
            // освобождаем слот дедупа; сам сидинг уже завершился.
            unawaited(_inFlight.remove(islandId));
          }
        },
      );
    });

    // Ошибка сидинга не должна блокировать остальные острова очереди
    // (переиспользовать отменённый Future нельзя), но вернётся
    // вызывающему через `operation`.
    _globalTail = operation.then((_) {}, onError: (_) {});

    return operation;
  }


  Future<void> _ensureSeededInternal(String islandId) async {

    final db = DatabaseService.instance;

    final manifest =
        await const ContentLoader().loadManifest(
      '${locationAssetBase(islandId)}/manifest.json',
    );

    final rows = db.select(
      'SELECT content_version FROM islands WHERE id = ?',
      [islandId],
    );

    if (rows.isNotEmpty && rows.first['content_version'] == manifest.version) {

      AppLogger.info(
        '[ContentSeeder] $islandId уже засеян (content_version='
        '${manifest.version}), пропускаем',
      );

      return;
    }

    // Каскадом сносит pois/trails и все связанные таблицы.
    // Ассеты грузим ДО открытия транзакции: BEGIN держится на общем
    // соединении, и пока транзакция открыта, FavoritesStore не может
    // писать избранное — при сбое сидинга ROLLBACK молча откатил бы
    // и пользовательские данные. Здесь транзакция — короткая и
    // чисто синхронная (только INSERT).
    final pois = await _loadPois(
      '${locationAssetBase(islandId)}/${manifest.poi}',
    );

    final trails = await _loadTrails(
      locationAssetBase(islandId),
      manifest,
    );

    db.execute('BEGIN');
    try {
      db.execute('DELETE FROM islands WHERE id = ?', [islandId]);

      _insertIsland(db, manifest);

      _insertPois(
        db,
        islandId,
        pois,
      );

      _insertTrails(
        db,
        islandId,
        trails,
      );

      db.execute('COMMIT');

      AppLogger.info(
        '[ContentSeeder] Контент острова "${manifest.name}" загружен в базу: '
        '${pois.length} POI, ${trails.length} маршрутов '
        '(content_version=${manifest.version})',
      );
    } catch (e) {
      try {
        db.execute('ROLLBACK');
      } catch (_) {}
      rethrow;
    }
  }


  void _insertIsland(
    DatabaseService db,
    Manifest manifest,
  ) {

    db.execute(
      '''
      INSERT INTO islands (
        id, name, language, country, stub, map_asset, source_layer,
        map_center_lat, map_center_lng,
        map_bounds_west, map_bounds_south, map_bounds_east, map_bounds_north,
        island_bounds_west, island_bounds_south, island_bounds_east, island_bounds_north,
        content_version, seeded_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ''',
      [
        manifest.id,
        manifest.name,
        manifest.language,
        manifest.country,
        manifest.stub ? 1 : 0,
        manifest.map,
        manifest.sourceLayer,
        manifest.mapCenter?.lat,
        manifest.mapCenter?.lng,
        manifest.mapBounds?.west,
        manifest.mapBounds?.south,
        manifest.mapBounds?.east,
        manifest.mapBounds?.north,
        manifest.islandBounds?.west,
        manifest.islandBounds?.south,
        manifest.islandBounds?.east,
        manifest.islandBounds?.north,
        manifest.version,
        DateTime.now().millisecondsSinceEpoch,
      ],
    );
  }


  Future<List<Poi>> _loadPois(
    String assetPath,
  ) async {

    final raw = await rootBundle.loadString(
      assetPath,
    );

    // Крупный poi.json (bay — 122 КБ) разбирается вне главного
    // изолята: compute (P1-3, 6-й проход).
    return parsePoisJson(raw);
  }


  /// Загружает маршруты из GeoJSON, если в пакете есть точки; иначе —
  /// из GPX; иначе — пустой список.
  ///
  /// Порядок тот же, что в `MapDataRepositoryWeb.loadTrails`: GeoJSON —
  /// основной формат (GPX зарегистрирован не у всех локаций —
  /// например, его нет у kekova). Пустой GeoJSON (например `[]` у coast)
  /// считается фолбэком на GPX — как и на web.
  Future<List<Trail>> _loadTrails(
    String assetBasePath,
    Manifest manifest,
  ) async {

    final geoJson = await _tryLoadTrailsGeoJson(
      '$assetBasePath/${manifest.trails}',
    );

    if (geoJson != null && geoJson.isNotEmpty) {
      return geoJson;
    }

    final gpx = await _tryLoadTrailsGpx(
      '$assetBasePath/trails.gpx',
    );

    if (gpx != null) {
      return gpx;
    }

    return const <Trail>[];
  }


  /// Пытается прочитать маршруты из GeoJSON.
  ///
  /// Возвращает `null`, если GeoJSON в пакете острова отсутствует.
  Future<List<Trail>?> _tryLoadTrailsGeoJson(String assetPath) async {

    try {

      final raw = await rootBundle.loadString(assetPath);

      return parseTrailsGeoJson(raw);

    } catch (_) {

      // GeoJSON не зарегистрирован в ассетах — фолбэк на GPX.
      return null;
    }
  }


  /// Пытается прочитать маршруты из GPX-файла.
  ///
  /// Возвращает `null`, если GPX в пакете острова отсутствует.
  Future<List<Trail>?> _tryLoadTrailsGpx(String assetPath) async {

    try {

      final raw = await rootBundle.loadString(assetPath);

      return parseTrailsGpx(raw);

    } catch (_) {

      // GPX не зарегистрирован в ассетах — фолбэк на GeoJSON.
      return null;
    }
  }


  void _insertPois(
    DatabaseService db,
    String islandId,
    List<Poi> pois,
  ) {

    // Подготовленные выражения: SQL разбирается один раз на
    // таблицу, а не на каждую строку (P1-7, 7-й проход).
    db.insertBatch(
      '''
      INSERT INTO pois (
        id, island_id, title, latitude, longitude,
        radius, description, audio_path, audio_ms, wave,
        video_path, category, number, sort_order
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ''',
      [
        for (var sortOrder = 0; sortOrder < pois.length; sortOrder++)
          () {
            final poi = pois[sortOrder];

            return [
              poi.id,
              islandId,
              poi.title,
              poi.latitude,
              poi.longitude,
              poi.radius,
              poi.description,
              poi.audioPath,
              poi.audioMs,
              poi.wave,
              poi.videoPath,
              poi.category,
              poi.number,
              sortOrder,
            ];
          }(),
      ],
    );

    db.insertBatch(
      '''
      INSERT INTO poi_images (island_id, poi_id, path, sort_order)
      VALUES (?, ?, ?, ?)
      ''',
      [
        for (var i = 0; i < pois.length; i++)
          for (var j = 0; j < pois[i].imagePaths.length; j++)
            [islandId, pois[i].id, pois[i].imagePaths[j], j],
      ],
    );

    db.insertBatch(
      '''
      INSERT INTO poi_trails (island_id, poi_id, trail_id)
      VALUES (?, ?, ?)
      ''',
      [
        for (final poi in pois)
          for (final trailId in poi.trailIds)
            [islandId, poi.id, trailId],
      ],
    );
  }


  void _insertTrails(
    DatabaseService db,
    String islandId,
    List<Trail> trails,
  ) {

    db.insertBatch(
      '''
      INSERT INTO trails (id, island_id, name, description, distance)
      VALUES (?, ?, ?, ?, ?)
      ''',
      [
        for (final trail in trails)
          [
            trail.id,
            islandId,
            trail.name,
            trail.description,
            trail.distance,
          ],
      ],
    );

    db.insertBatch(
      '''
      INSERT INTO trail_points (
        island_id, trail_id, line_index,
        point_id, point_order, latitude, longitude, elevation
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
      ''',
      [
        for (final trail in trails)
          for (var lineIndex = 0;
              lineIndex < trail.segments.length;
              lineIndex++)
            for (final point in trail.segments[lineIndex])
              [
                islandId,
                trail.id,
                lineIndex,
                point.id,
                point.order,
                point.latitude,
                point.longitude,
                // Высота из GPX/GeoJSON (A1): null у побережий без
                // рельефа — профиль тогда не строится.
                point.elevation,
              ],
      ],
    );

    db.insertBatch(
      '''
      INSERT INTO trail_images (island_id, trail_id, path, sort_order)
      VALUES (?, ?, ?, ?)
      ''',
      [
        for (final trail in trails)
          for (var i = 0; i < trail.imagePaths.length; i++)
            [islandId, trail.id, trail.imagePaths[i], i],
      ],
    );
  }
}