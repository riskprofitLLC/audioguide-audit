import 'package:flutter/material.dart';

import '../../../app/theme.dart';

/// Информация о категории POI: человекочитаемое название и
/// SDF-иконка маркера карты (файл в `assets/map_icons/`).
///
/// ЕДИНЫЙ источник для карты, легенды и hero-плейсхолдера:
/// плоский глиф ([glyph]) — производная ТОЙ ЖЕ иконки из
/// `assets/map_icons_flat/`, поэтому «бумажный» плейсхолдер
/// точки без фото больше не расходится с её маркером
/// (P0-8, 5-й проход).
class PoiCategoryInfo {
  const PoiCategoryInfo(this.label, this.mapIcon);

  final String label;

  /// Файл SDF-иконки маркера; `null` — фолбэк poi-default
  /// (булавка), как и на карте.
  final String? mapIcon;

  /// Плоская копия иконки для hero-плейсхолдера и чипов
  /// легенды (assets/map_icons_flat/).
  String get glyph =>
      'assets/map_icons_flat/${mapIcon ?? 'map-pin.png'}';
}

/// Таблица категория → (название, иконка карты). Раньше карта
/// держала свою таблицу из 23 иконок, а hero-плейсхолдер —
/// свою из ~10: museum, tomb, square, book, aquarium и др.
/// получали map-pin и расходились с маркером.
const Map<String, PoiCategoryInfo> kPoiCategories = {
  'anchor': PoiCategoryInfo('Якорная стоянка', 'anchor.png'),
  'aquarium': PoiCategoryInfo('Аквариум', 'fish.png'),
  'bay': PoiCategoryInfo('Бухта', null),
  'beach': PoiCategoryInfo('Пляж', 'umbrella-beach.png'),
  'book': PoiCategoryInfo('Библиотека', 'book-open.png'),
  'cape': PoiCategoryInfo('Мыс', 'mountain.png'),
  'cathedral': PoiCategoryInfo('Собор', 'church.png'),
  'cave': PoiCategoryInfo('Пещера', null),
  'church': PoiCategoryInfo('Церковь', 'church.png'),
  'cistern': PoiCategoryInfo('Цистерна', null),
  'city': PoiCategoryInfo('Город', null),
  'entrance': PoiCategoryInfo('Вход', 'entrance.png'),
  'fort': PoiCategoryInfo('Крепость', 'fort-awesome.png'),
  'gallery': PoiCategoryInfo('Галерея', 'route.png'),
  'island': PoiCategoryInfo('Остров', null),
  'lake': PoiCategoryInfo('Озеро', 'water.png'),
  'lighthouse': PoiCategoryInfo('Маяк', 'tower-observation.png'),
  'monastery': PoiCategoryInfo('Монастырь', null),
  'monument': PoiCategoryInfo('Памятник', null),
  'mosque': PoiCategoryInfo('Мечеть', null),
  'museum': PoiCategoryInfo('Музей', 'landmark.png'),
  'necropolis': PoiCategoryInfo('Некрополь', null),
  'park': PoiCategoryInfo('Парк', 'tree.png'),
  'peak': PoiCategoryInfo('Вершина', 'volcano.png'),
  'railway': PoiCategoryInfo('Железная дорога', 'train.png'),
  'ruins': PoiCategoryInfo('Руины', null),
  'shrine': PoiCategoryInfo('Святилище', 'torii-gate.png'),
  'ski': PoiCategoryInfo('Горнолыжный курорт', 'skiing.png'),
  'square': PoiCategoryInfo('Площадь', 'monument.png'),
  'street': PoiCategoryInfo('Улица', null),
  'tomb': PoiCategoryInfo('Гробница', 'archway.png'),
  'tower': PoiCategoryInfo('Башня', null),
  'university': PoiCategoryInfo('Университет', 'school.png'),
  'valley': PoiCategoryInfo('Долина', null),
  'viewpoint': PoiCategoryInfo('Смотровая', 'binoculars.png'),
  'village': PoiCategoryInfo('Деревня', null),
  'water': PoiCategoryInfo('Источник', 'water.png'),
};

/// Название категории по её id, «Место» — если категории нет.
String poiCategoryLabel(String? id) {
  if (id == null) return 'Место';

  return kPoiCategories[id]?.label ?? 'Место';
}

/// Глиф категории — плоская копия иконки её МАРКЕРА
/// (assets/map_icons_flat/): hero-плейсхолдер точки без фото
/// показывает тот же знак, что стоит на карте.
String poiCategoryGlyph(String? id) {
  if (id == null) return 'assets/map_icons_flat/map-pin.png';

  return kPoiCategories[id]?.glyph ??
      'assets/map_icons_flat/map-pin.png';
}

/// Файл SDF-иконки маркера карты для категории; `null` —
/// фолбэк poi-default (map-icons/map-pin.png), как в
/// map_layers.dart.
String? poiCategoryMapIcon(String? id) {
  if (id == null) return null;

  return kPoiCategories[id]?.mapIcon;
}

/// Оттенок глифа категории — морская глубина для водных и
/// прибрежных объектов, чернила для остальных.
Color poiCategoryGlyphColor(String? id) {
  switch (id) {
    case 'bay':
    case 'beach':
    case 'anchor':
    case 'island':
    case 'lake':
    case 'water':
    case 'cistern':
      return AppColors.depth;
    default:
      // Чернила недоступны (функция без контекста), а глубинная
      // бирюза читается на песочных плашках в обеих темах.
      return AppColors.depth;
  }
}
