/// Манифест офлайн-пакета острова.
///
/// Отражает структуру `content/<island_id>/manifest.json`.
library;

class Manifest {


  const Manifest({
    required this.id,
    required this.name,
    required this.version,
    required this.language,
    required this.map,
    required this.trails,
    required this.poi,
    required this.audio,
    required this.images,
    this.country = '',
    this.stub = false,
    this.sourceLayer,
    this.mapCenter,
    this.mapBounds,
    this.islandBounds,
    this.hikingForbidden = false,
    this.trailNotice,
    this.transport,
    this.boatSpeedKmh,
    this.presetCollections,
    this.poiScaleFactor = 1.0,
    this.poiLabelScaleFactor = 1.0,
    this.fitZoomAdjustment = 0.0,
    this.fitCenterAdjustment,
    this.trailHitTest = true,
  });



  final String id;


  final String name;


  final int version;


  final String language;


  /// Путь к архиву PMTiles внутри пакета (например,
  /// `map.pmtiles`). Может быть пустым, если у острова
  /// нет офлайн-карты.
  final String map;


  final String trails;


  final String poi;


  final String audio;


  final String images;


  /// Имя векторного слоя внутри архива PMTiles.
  ///
  /// Задаётся при сборке тайлов (tippecanoe `-L`). Если
  /// не указано — используется идентификатор острова.
  final String? sourceLayer;


  /// Имя слоя карты по умолчанию.
  String get effectiveSourceLayer =>
      sourceLayer ?? id;


  /// Страна, где находится остров («Турция»...).
  /// Задаётся в манифесте (`{"country": "Турция"}`); используется
  /// переключателем стран на главном экране.
  final String country;


  /// Остров-заглушка: материал (POI, маршруты, фото, аудио) ещё
  /// не собран. На главной показывается надпись «в разработке».
  final bool stub;


  /// Координаты по умолчанию для центра карты острова
  /// (`{"lat": ..., "lng": ...}`). Опционально.
  final MapCenter? mapCenter;


  /// Границы офлайн-карты острова
  /// (`{"west": ..., "south": ..., "east": ..., "north": ...}`).
  /// Опционально; используются для подгонки стартовой камеры
  /// под весь остров.
  final MapBounds? mapBounds;



  /// Границы именно суши острова (`{"west": ..., "south": ...,
  /// "east": ..., "north": ...}`) — реальный контур береговой
  /// линии. Опционально; используются для подгонки стартовой
  /// камеры под весь остров (а не только под маршруты).
  final MapBounds? islandBounds;


  /// Пешие маршруты запрещены (остров — охраняемая зона).
  ///
  /// Если `true`, на главной вместо списка маршрутов показывается
  /// пометка из [trailNotice].
  final bool hikingForbidden;


  /// Пояснение к запрету пеших маршрутов.
  final String? trailNotice;

  /// Тип перемещения локации (П3, 12-й проход): `boat` —
  /// морская прогулка (осмотр с воды), `walk`/`null` — пешком.
  final String? transport;

  /// Скорость перемещения по воде для оценки времени маршрута
  /// (км/ч, только для `transport: "boat"`; дефолт 8). Прежняя
  /// оценка «на воде» считалась по пешеходным 4 км/ч (баг 16,
  /// замечания Sonnet).
  final double? boatSpeedKmh;

  /// Эффективная скорость на воде (км/ч).
  double get effectiveBoatSpeedKmh => boatSpeedKmh ?? 8.0;

  /// Готовые подборки РЕГИОНА (П8, 12-й проход): редактированию
  /// не подлежат, живут в манифесте региона.
  final List<PresetCollection>? presetCollections;

  /// Локация морская — осмотры с воды.
  bool get isBoat => transport == 'boat';


  /// Множитель размера маркеров POI на карте.
  ///
  /// Меньше 1 — мельче маркеры (остров маленький и камера
  /// подводится близко). Было хардкодом по id острова в
  /// `map_layers.dart`, теперь задаётся в манифесте.
  final double poiScaleFactor;


  /// Множитель размера подписей POI на карте.
  ///
  /// Отдельный от [poiScaleFactor]: текст уменьшается не так
  /// сильно, как маркеры, иначе SDF-глифы сливаются.
  final double poiLabelScaleFactor;


  /// Поправка к зум-уровню при подгонке камеры под остров.
  ///
  /// Отрицательное — камеру отодвинуть (остров целиком в кадре),
  /// положительное — приблизить. Было хардкодом kekova в
  /// `map_camera.dart`.
  final double fitZoomAdjustment;


  /// Сдвиг центра камеры при подгонке под остров
  /// (`{"lat": ..., "lng": ...}`), в градусах.
  ///
  /// Накладывается на целевую точку камеры после расчёта подгонки:
  /// [MapCenter.lat] смещает камеру по широте на указанную долю
  /// градуса, [MapCenter.lng] — по долготе. Используется, чтобы
  /// остров визуально стоял по центру превью, когда масса его суши
  /// не совпадает с центром маршрутов/границ.
  final MapCenter? fitCenterAdjustment;


  /// Участвуют ли линии маршрутов в tap-семантике карты
  /// (`"trailHitTest": false` в манифесте). По умолчанию — да.
  /// На Гемилере маршрут один и проходит ЧЕРЕЗ точки: попадание
  /// линии перекрывало тап по POI, поэтому там выключено
  /// (P2, 5-й проход: раньше был хардкод id в map_taps.dart).
  final bool trailHitTest;



  factory Manifest.fromJson(
    Map<String, dynamic> json,
  ) {

    return Manifest(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      version: json['version'] as int? ?? 1,
      language: json['language'] as String? ?? 'ru',
      map: json['map'] as String? ?? '',
      trails: json['trails'] as String? ?? '',
      poi: json['poi'] as String? ?? '',
      audio: json['audio'] as String? ?? 'audio',
      images: json['images'] as String? ?? 'images',
      country: json['country'] as String? ?? '',
      stub: json['stub'] as bool? ?? false,
      sourceLayer: json['sourceLayer'] as String?,
      mapCenter: json['mapCenter'] == null
          ? null
          : MapCenter.fromJson(
              json['mapCenter'] as Map<String, dynamic>,
            ),
      mapBounds: json['mapBounds'] == null
          ? null
          : MapBounds.fromJson(
              json['mapBounds'] as Map<String, dynamic>,
            ),
      islandBounds: json['islandBounds'] == null
          ? null
          : MapBounds.fromJson(
              json['islandBounds'] as Map<String, dynamic>,
            ),
      hikingForbidden: json['hikingForbidden'] as bool? ?? false,
      trailNotice: json['trailNotice'] as String?,
      transport: json['transport'] as String?,
      boatSpeedKmh: (json['boatSpeedKmh'] as num?)?.toDouble(),
      presetCollections: (json['collections'] as List<dynamic>?)
          ?.whereType<Map<String, dynamic>>()
          .map(PresetCollection.fromJson)
          .toList(),
      poiScaleFactor:
          (json['poiScaleFactor'] as num?)?.toDouble() ?? 1.0,
      poiLabelScaleFactor:
          (json['poiLabelScaleFactor'] as num?)?.toDouble() ?? 1.0,
      fitZoomAdjustment:
          (json['fitZoomAdjustment'] as num?)?.toDouble() ?? 0.0,
      fitCenterAdjustment: json['fitCenterAdjustment'] == null
          ? null
          : MapCenter.fromJson(
              json['fitCenterAdjustment'] as Map<String, dynamic>,
            ),
      trailHitTest: json['trailHitTest'] as bool? ?? true,
    );
  }
}


/// Координаты дефолтного центра карты острова.
class MapCenter {


  const MapCenter({
    required this.lat,
    required this.lng,
  });


  final double lat;

  final double lng;


  factory MapCenter.fromJson(
    Map<String, dynamic> json,
  ) {
    return MapCenter(
      lat: (json['lat'] as num).toDouble(),
      lng: (json['lng'] as num).toDouble(),
    );
  }
}


/// Границы офлайн-карты острова.
///
/// Прямоугольник в географических координатах: западная
/// и восточная долготы, южная и северная широты.
class MapBounds {


  const MapBounds({
    required this.west,
    required this.south,
    required this.east,
    required this.north,
  });


  final double west;


  final double south;


  final double east;


  final double north;


  factory MapBounds.fromJson(
    Map<String, dynamic> json,
  ) {
    return MapBounds(
      west: (json['west'] as num).toDouble(),
      south: (json['south'] as num).toDouble(),
      east: (json['east'] as num).toDouble(),
      north: (json['north'] as num).toDouble(),
    );
  }
}


/// Готовая подборка региона из манифеста (П8, 12-й проход).
class PresetCollection {
  const PresetCollection({required this.name, required this.keys});

  /// Название подборки («Гемилер: главные виды»).
  final String name;

  /// Ключи точек «локация/poi-XX» в порядке показа.
  final List<String> keys;

  factory PresetCollection.fromJson(Map<String, dynamic> json) =>
      PresetCollection(
        name: json['name'] as String,
        keys: [
          for (final key in (json['pois'] as List).whereType<String>()) key,
        ],
      );
}
