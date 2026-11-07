/// Точка интереса (POI).
///
/// Содержит координаты, описание, фото и аудио.
library;

import '../../content/models/region_catalog.dart';

class Poi {


  const Poi({
    required this.id,
    required this.title,
    required this.latitude,
    required this.longitude,
    this.radius,
    this.description,
    this.audioPath,
    this.audioMs,
    this.wave,
    this.videoPath,
    this.imagePaths = const [],
    this.trailIds = const [],
    this.category,
    this.number,
  });



  final String id;


  final String title;


  final double latitude;


  final double longitude;


  /// Радиус срабатывания голосового гида (метры).
  final double? radius;


  final String? description;


  final String? audioPath;


  /// Длительность аудио в миллисекундах из poi.json (A8, 8-й
  /// проход). Пишет tool/generate_audio.py (--durations-only
  /// тоже). Плеер показывает длительность сразу, не грузя весь
  /// mp3 через rootBundle ради одной цифры; на web это была
  /// двойная загрузка вместе с плеером.
  final int? audioMs;


  /// Огибающая громкости аудио — base64, 80 значений 0–255
  /// (RMS по окнам, нормирован на пик). Плеер рисует реальную
  /// волну; null/битая строка — декоративный фолбэк (B5).
  final String? wave;


  /// Путь к видеофайлу точки (в `images/<id>/`), если есть.
  final String? videoPath;


  final List<String> imagePaths;


  /// Маршруты, в состав которых входит точка интереса.
  ///
  /// Пустой список означает, что достопримечательность
  /// пока не привязана ни к одному маршруту.
  final List<String> trailIds;


  /// Категория точки интереса для иконки на карте.
  ///
  /// Например: `church`, `lighthouse`, `museum`, `beach`.
  /// Используется картой для выбора icon-image маркера.
  final String? category;


  /// Порядковый номер достопримечательности для подписи на карте.
  ///
  /// Задаётся явно в `poi.json` (`"number": 3`). Если поле
  /// отсутствует у всех точек острова, используется порядок
  /// следования в `poi.json` (см. `map_widget.dart`).
  final int? number;


  /// Полный путь к аудио-ассету точки:
  /// `content/<регион>/<локация>/audio/<audioPath>`.
  ///
  /// Путь строится в одном месте, чтобы не разъезжались форматы
  /// при рефакторингах структуры контента (`way/no-way` и т.п.).
  String audioAssetPath(String islandId) {
    return '${locationAssetBase(islandId)}/audio/$audioPath';
  }



  factory Poi.fromJson(
    Map<String, dynamic> json,
  ) {

    final id = json['id'] as String?;
    final title = json['title'] as String?;
    final lat = json['latitude'] as num?;
    final lng = json['longitude'] as num?;

    if (id == null || id.isEmpty) {
      throw const FormatException('POI missing required field "id"');
    }
    if (title == null || title.isEmpty) {
      throw FormatException('POI "$id" missing required field "title"');
    }
    if (lat == null || lng == null) {
      throw FormatException('POI "$id" missing required coordinates');
    }

    return Poi(
      id: id,
      title: title,
      latitude: lat.toDouble(),
      longitude: lng.toDouble(),
      radius:
          (json['radius'] as num?)?.toDouble(),
      description: json['description'] as String?,
      audioPath: json['audio'] as String?,
      audioMs: (json['audioMs'] as num?)?.toInt(),
      wave: json['wave'] as String?,
      videoPath: json['video'] as String?,
      imagePaths:
          (json['images'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      trailIds:
          (json['trails'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      category: json['category'] as String?,
      number: (json['number'] as num?)?.toInt(),
    );
  }
}


/// Проверяет, что id POI в списке уникальны.
///
/// Дубликаты id приводят к PRIMARY KEY-конфликту в SQLite при сидинге
/// (`island_id, id`), а на web — к тихому неверному поведению карты,
/// избранного и нумерации папок (`poi_sort.folderNumberFor`).
/// Действительные данные проверяются при загрузке `poi.json`.
void validateUniquePoiIds(List<Poi> pois) {

  final seen = <String>{};

  for (final poi in pois) {

    if (!seen.add(poi.id)) {

      throw FormatException(
        'Дубликат id POI "${poi.id}" в poi.json',
      );
    }
  }
}
