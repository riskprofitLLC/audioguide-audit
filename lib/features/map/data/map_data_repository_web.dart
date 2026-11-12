import 'package:flutter/services.dart';

import '../../../core/utils/logger.dart';
import '../../content/models/region_catalog.dart';
import '../../content/services/geojson_trails_parser.dart';
import '../../content/services/gpx_trails_parser.dart';
import '../../content/services/markdown_blocks.dart';
import '../../content/services/poi_text_loader.dart';
import '../../poi/models/poi.dart';
import '../../poi/services/poi_json_parser.dart';
import '../../trails/models/trail.dart';


/// Репозиторий данных карты.
///
/// Читает POI и маршруты напрямую из офлайн-ассетов
/// острова. Работает одинаково на нативных платформах
/// и на web (в отличие от SQLite, который на web
/// недоступен).

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

    final raw = await rootBundle.loadString(
      '$_basePath/poi.json',
    );

    // Крупный JSON (bay — 122 КБ) разбирается вне главного
    // изолята: compute (P1-3, 6-й проход).
    final pois = await parsePoisJson(raw);

    AppLogger.info('[MapDataRepository] loadPois island=$islandId -> ${pois.length}');

    return pois;
  }


  Future<List<Trail>> loadTrails() async {

    AppLogger.info('[MapDataRepository] loadTrails island=$islandId');

    // GeoJSON — основной формат маршрутов (есть у ВСЕХ локаций;
    // GPX зарегистрирован не везде — например у kekova его нет).
    // Пробуем его первым, чтобы не получать 404-откликов сети
    // на пробах отсутствующих GPX в консоли.
    final geoJson = await _tryLoadTrailsGeoJson();

    if (geoJson != null && geoJson.isNotEmpty) {

      AppLogger.infoFn(
        () => '[MapDataRepository] loadTrails island=$islandId -> GeoJSON '
            '${geoJson.map((t) => t.name).toList()}',
      );

      return geoJson;
    }

    final gpx = await _tryLoadTrailsGpx();

    if (gpx != null) {

      AppLogger.infoFn(
        () => '[MapDataRepository] loadTrails island=$islandId -> GPX '
            '${gpx.map((t) => t.name).toList()}',
      );

      return gpx;
    }

    AppLogger.info(
      '[MapDataRepository] loadTrails island=$islandId -> нет маршрутов',
    );

    return const [];
  }


  /// Пытается прочитать маршруты из GeoJSON.
  ///
  /// Возвращает `null`, если GeoJSON в пакете локации отсутствует.
  Future<List<Trail>?> _tryLoadTrailsGeoJson() async {

    try {

      final raw = await rootBundle.loadString(
        '$_basePath/trails.geojson',
      );

      return parseTrailsGeoJson(raw);

    } catch (_) {

      // GeoJSON не зарегистрирован в ассетах — фолбэк на GPX.
      return null;
    }
  }


  /// Пытается прочитать маршруты из GPX-файла.
  ///
  /// Возвращает `null`, если GPX в пакете острова отсутствует.
  Future<List<Trail>?> _tryLoadTrailsGpx() async {

    try {

      final raw = await rootBundle.loadString(
        '$_basePath/trails.gpx',
      );

      return parseTrailsGpx(raw);

    } catch (_) {

      // GPX не зарегистрирован в ассетах — фолбэк на GeoJSON.
      return null;
    }
  }


  /// Полный текст POI СТРУКТУРОЙ блоков markdown (B3.4).
  ///
  /// [folderNumber] — номер файла в папке `text/` (нумерация как
  /// на карте). Файл ищется по префиксу `NN - ` среди ассетов
  /// острова. Возвращает `null`, если файл не найден.
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