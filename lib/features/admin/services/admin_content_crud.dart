/// Чистые функции CRUD над контентом админ-панели: poi.json,
/// манифесты регионов/локаций и Dart-каталог регион_catalog.
///
/// Вся работа с GitHub — в [AdminContentOps] и [GitHubContentService];
/// здесь только преобразования строк/JSON, тестируются без сети.
library;

import 'dart:convert';

// --- poi.json ---

/// Декодирует сырой poi.json в список точек.
List<Map<String, Object?>> parsePoiList(String rawJson) {
  final decoded = jsonDecode(rawJson);

  if (decoded is! List<Object?>) {
    throw const FormatException('poi.json — не список');
  }

  return decoded
      .whereType<Map<String, Object?>>()
      .map((e) => Map<String, Object?>.of(e))
      .toList();
}

String _encodePois(List<Map<String, Object?>> pois) =>
    const JsonEncoder.withIndent(' ').convert(pois);

/// `poi-07` из номера 7 (два знака, как в каталоге).
String poiIdForNumber(int number) =>
    'poi-${number.toString().padLeft(2, '0')}';

/// Следующий свободный номер id (`poi-NN`): максимум суффиксов
/// существующих id + 1 (минимум 1).
int nextPoiIdNumber(String rawJson) {
  var max = 0;

  for (final poi in parsePoiList(rawJson)) {
    final id = poi['id'] as String? ?? '';

    final match = RegExp(r'^poi-(\d+)$').firstMatch(id);

    if (match != null) {
      final n = int.parse(match.group(1)!);

      if (n > max) {
        max = n;
      }
    }
  }

  return max + 1;
}

/// Папочный номер (`NN - …`) для НОВОЙ точки, добавленной в конец
/// poi.json без явного `number`: повторяет [folderNumberFor] —
/// maxNumber среди пронумерованных + позиция среди внемаршрутных.
int nextFolderNumberForNewPoi(String rawJson) {
  final pois = parsePoiList(rawJson);

  var maxNumber = 0;
  var unnumbered = 0;

  for (final poi in pois) {
    final number = poi['number'];

    if (number is num) {
      if (number.toInt() > maxNumber) {
        maxNumber = number.toInt();
      }
    } else {
      unnumbered++;
    }
  }

  return maxNumber + unnumbered + 1;
}

/// Папочный номер существующей точки по её id (0 — точки нет).
int folderNumberOfPoi(String rawJson, String poiId) {
  final pois = parsePoiList(rawJson);

  var maxNumber = 0;
  var unnumbered = 0;

  for (final poi in pois) {
    final number = poi['number'];

    if (number is num) {
      if (number.toInt() > maxNumber) {
        maxNumber = number.toInt();
      }
    }
  }

  for (final poi in pois) {
    if (poi['number'] != null) {
      if (poi['id'] == poiId) {
        return (poi['number'] as num).toInt();
      }
    } else {
      unnumbered++;

      if (poi['id'] == poiId) {
        return maxNumber + unnumbered;
      }
    }
  }

  return 0;
}

/// Шаблон новой точки: без аудио и фото, с пустым описанием.
Map<String, Object?> buildNewPoi({
  required String id,
  required String title,
  required double latitude,
  required double longitude,
  double? radius,
  String? category,
  int? number,
  List<String> trails = const [],
}) {
  final poi = <String, Object?>{
    'id': id,
    'title': title,
    'latitude': latitude,
    'longitude': longitude,
    'description': '',
    'images': <String>[],
    'trails': trails,
  };

  if (radius != null) {
    poi['radius'] = radius;
  }

  if (category != null && category.isNotEmpty) {
    poi['category'] = category;
  }

  if (number != null) {
    poi['number'] = number;
  }

  return poi;
}

/// Добавляет точку в конец poi.json.
String addPoiToJson(String rawJson, Map<String, Object?> poi) {
  final pois = parsePoiList(rawJson);

  pois.add(poi);

  return _encodePois(pois);
}

/// Убирает точку из poi.json по id.
String removePoiFromJson(String rawJson, String poiId) {
  final pois = parsePoiList(rawJson);

  pois.removeWhere((poi) => poi['id'] == poiId);

  return _encodePois(pois);
}

/// Сливает поля в точку poi.json: значение null удаляет ключ.
String updatePoiJsonFields(
  String rawJson,
  String poiId,
  Map<String, Object?> fields,
) {
  final pois = parsePoiList(rawJson);

  final updated = pois.map((poi) {
    if (poi['id'] != poiId) {
      return poi;
    }

    final copy = Map<String, Object?>.of(poi);

    for (final entry in fields.entries) {
      if (entry.value == null) {
        copy.remove(entry.key);
      } else {
        copy[entry.key] = entry.value;
      }
    }

    return copy;
  }).toList();

  return _encodePois(updated);
}

/// Сырая запись точки из poi.json (null — точки нет).
Map<String, Object?>? poiRecordFromJson(String rawJson, String poiId) {
  for (final poi in parsePoiList(rawJson)) {
    if (poi['id'] == poiId) {
      return poi;
    }
  }

  return null;
}

// --- текстовый файл точки ---

/// Имя файла текста: `07 - Название.md`.
String poiTextFileName(int folderNumber, String title) =>
    '${folderNumber.toString().padLeft(2, '0')} - $title.md';

/// Содержимое нового текстового файла (H1 обязателен —
/// sync_texts.py и читалка от него отталкиваются).
String newPoiTextContent(String title) => '# $title\n\n';

/// Папка текста (`way`/`no-way`): маршрутная точка — в `way`,
/// внемаршрутная — в `no-way`.
String poiTextSubdir(List<String> trails) =>
    trails.isEmpty ? 'no-way' : 'way';

// --- манифесты ---

/// Минимальный манифест новой локации (без карты — растровый
/// OSM-фолбэк, как у kilikia).
String buildLocationManifestJson(String id, String name) {
  final manifest = <String, Object?>{
    'id': id,
    'name': name,
    'country': 'Турция',
    'version': 1,
    'language': 'ru',
    'map': '',
    'trails': 'trails.geojson',
    'poi': 'poi.json',
    'audio': 'audio',
    'images': 'images',
  };

  return const JsonEncoder.withIndent(' ').convert(manifest);
}

/// Пустой список точек новой локации.
const String emptyPoiJson = '[]';

/// Пустой GeoJSON маршрутов новой локации.
String emptyTrailsGeoJson() =>
    const JsonEncoder.withIndent(' ').convert({
      'type': 'FeatureCollection',
      'features': <Object>[],
    });

/// Добавляет id локации в список `locations` манифеста региона.
String addLocationToRegionManifest(String rawJson, String locationId) {
  final manifest = jsonDecode(rawJson) as Map<String, Object?>;

  final copy = Map<String, Object?>.of(manifest);

  final locations = (copy['locations'] as List<Object?>? ?? [])
      .map((e) => e.toString())
      .toList();

  if (!locations.contains(locationId)) {
    locations.add(locationId);
  }

  copy['locations'] = locations;

  return const JsonEncoder.withIndent(' ').convert(copy);
}

/// Убирает id локации из списка `locations` манифеста региона.
String removeLocationFromRegionManifest(String rawJson, String locationId) {
  final manifest = jsonDecode(rawJson) as Map<String, Object?>;

  final copy = Map<String, Object?>.of(manifest);

  final locations = (copy['locations'] as List<Object?>? ?? [])
      .map((e) => e.toString())
      .where((id) => id != locationId)
      .toList();

  copy['locations'] = locations;

  return const JsonEncoder.withIndent(' ').convert(copy);
}

// --- Dart-каталог регионов (region_catalog.dart) ---

/// Путь каталога в репозитории.
const String kRegionCatalogPath =
    'lib/features/content/models/region_catalog.dart';

/// Вставляет id локации в `locationIds` региона в исходнике каталога.
///
/// Ищет `id: '<regionId>'`, затем первый после него `locationIds: [`,
/// и добавляет запись перед закрывающей скобкой (в конец списка).
/// Бросает [FormatException], если регион или список не найдены.
String addLocationIdToCatalog(
  String source,
  String regionId,
  String locationId,
) {
  final regionIdx = source.indexOf("id: '$regionId'");

  if (regionIdx < 0) {
    throw FormatException('В каталоге нет региона $regionId');
  }

  final listIdx = source.indexOf('locationIds: [', regionIdx);

  if (listIdx < 0) {
    throw FormatException('У региона $regionId нет locationIds');
  }

  final openBracket = source.indexOf('[', listIdx);

  final closeBracket = source.indexOf(']', openBracket);

  if (closeBracket < 0) {
    throw const FormatException('Не закрыта скобка locationIds');
  }

  final inner = source.substring(openBracket + 1, closeBracket).trim();

  final entry = inner.isEmpty ? "'$locationId'" : "'$locationId', ";

  return source.replaceRange(
    openBracket + 1,
    openBracket + 1,
    entry,
  );
}

/// Убирает запись `'$locationId'` из исходника каталога
/// (и из однострочного `['a', 'b']`, и из многострочного списка).
/// Бросает [FormatException], если id не найден.
String removeLocationIdFromCatalog(String source, String locationId) {
  final patterns = [
    "'$locationId', ",
    "'$locationId',",
    ", '$locationId'",
    "'$locationId'",
  ];

  for (final pattern in patterns) {
    if (source.contains(pattern)) {
      return source.replaceFirst(pattern, '');
    }
  }

  throw FormatException('В каталоге нет локации $locationId');
}

/// Валидация slug id новой локации: латиница, цифры, дефис.
bool isValidLocationId(String id) =>
    RegExp(r'^[a-z0-9]+(-[a-z0-9]+)*$').hasMatch(id);
