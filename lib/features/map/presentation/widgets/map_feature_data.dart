part of 'map_widget.dart';


/// FeatureCollection точек интереса для карты.
Map<String, dynamic> _poiFeatureCollection(
  List<Poi> pois,
  List<String> poiLocations, {
  bool namespaced = false,
  Set<String>? favoriteKeys,
  Set<String>? listenedKeys,
}) {

  // Нумерация достопримечательностей на карте. Если у точек острова
  // явно задано поле `number` в poi.json — используем его. Точки без
  // номера подписываются без префикса «N. ». Если же поле `number`
  // не задано ни у одной точки — нумерация берётся
  // из порядка следования в poi.json.
  //
  // В режиме «все регионы» сквозная нумерация по всему каталогу
  // бессмысленна, поэтому используются только явные `number`.
  final useExplicitNumbers =
      namespaced || pois.any((poi) => poi.number != null);

  return {
    'type': 'FeatureCollection',
    'features': [
      for (var i = 0; i < pois.length; i++)
        _poiFeature(
          pois[i],
          poiLocations[i],
          // Номер без явного `number` — позиция в poi.json (индекс
          // цикла, а не indexOf: O(n²) на каждой пересборке
          // источника `pois`, включая переключение звезды).
          useExplicitNumbers ? pois[i].number : i + 1,
          namespaced: namespaced,
          // Ключ избранного у POI на карте — «локация/poi-XX»,
          // тот же, что и на странице деталей (`$islandId/$itemId`).
          isFavorite: favoriteKeys
                  ?.contains('${poiLocations[i]}/${pois[i].id}') ??
              false,
          // «Прослушано» (1b, 12-й проход): тот же формат ключа
          // «локация/poi-XX», что и у listenedSetProvider.
          isListened: listenedKeys
                  ?.contains('${poiLocations[i]}/${pois[i].id}') ??
              false,
        ),
    ],
  };
}


/// Одна GeoJSON-фича точки интереса.
///
/// В режиме «все регионы» id фичи составной — `локация/poi-XX`,
/// т.к. исходные id повторяются в каждой локации. Исходный id
/// сохраняется в `poiId`, локация — в `locationId`.
Map<String, dynamic> _poiFeature(
  Poi poi,
  String locationId,
  int? number, {
  bool namespaced = false,
  bool isFavorite = false,
  bool isListened = false,
}) {

  final featureId = namespaced ? '$locationId/${poi.id}' : poi.id;

  final label = number != null ? '$number. ${poi.title}' : poi.title;

  return {

    'type': 'Feature',

    'id': featureId,

    'properties': {
      'id': featureId,
      'poiId': poi.id,
      'locationId': locationId,
      'title': poi.title,
      'number': number,
      'label': label,
      'description': poi.description ?? '',
      'category': poi.category ?? '',
      'isFavorite': isFavorite,
      'isListened': isListened,
    },

    'geometry': {
      'type': 'Point',
      'coordinates': [
        poi.longitude,
        poi.latitude,
      ],
    },
  };
}


/// FeatureCollection выделенной точки интереса для слоёв
/// `poi-highlight-halo` и `poi-highlight-pulse`.
///
/// Пустая коллекция, если точка не задана.
Map<String, dynamic> _highlightPoiFeatureCollection(
  Poi? poi,
) {

  if (poi == null) {

    return {
      'type': 'FeatureCollection',
      'features': <Map<String, dynamic>>[],
    };
  }

  return {
    'type': 'FeatureCollection',
    'features': [
      {
        'type': 'Feature',

        'id': poi.id,

        'properties': {
          'id': poi.id,
        },

        'geometry': {
          'type': 'Point',
          'coordinates': [
            poi.longitude,
            poi.latitude,
          ],
        },
      },
    ],
  };
}


/// FeatureCollection маршрутов для карты.
Map<String, dynamic> _trailFeatureCollection(
  List<Trail> trails,
  List<String> trailLocations, {
  bool namespaced = false,
}) {

  return {
    'type': 'FeatureCollection',
    'features': [
      for (var i = 0; i < trails.length; i++)
        _trailFeature(trails[i], trailLocations[i], namespaced),
    ],
  };
}


/// Одна GeoJSON-фича маршрута.
///
/// Как и у POI: в режиме «все регионы» id фичи составной
/// (`локация/trail-XX`), исходный id — в `trailId`.
Map<String, dynamic> _trailFeature(
  Trail trail,
  String locationId,
  bool namespaced,
) {

  final featureId = namespaced ? '$locationId/${trail.id}' : trail.id;

  return {

    'type': 'Feature',

    'id': featureId,

    'properties': {
      'id': featureId,
      'trailId': trail.id,
      'locationId': locationId,
      'name': trail.name,
      'description': trail.description ?? '',
    },

    'geometry': _trailGeometry(trail),
  };
}
