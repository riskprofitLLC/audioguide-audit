// Русские названия категорий POI: бейдж на странице деталей
// показывает человекочитаемое слово, а не английский id.
// Таблица категорий — единый источник для карты, легенды и
// hero-плейсхолдера (P0-8, 5-й проход).

import 'package:flutter_test/flutter_test.dart';

import 'package:island_guide/features/poi/utils/poi_category.dart';

void main() {
  test('poiCategoryLabel переводит известные категории', () {
    expect(poiCategoryLabel('bay'), 'Бухта');
    expect(poiCategoryLabel('church'), 'Церковь');
    expect(poiCategoryLabel('lighthouse'), 'Маяк');
    expect(poiCategoryLabel('anchor'), 'Якорная стоянка');
    expect(poiCategoryLabel('beach'), 'Пляж');
    expect(poiCategoryLabel('cave'), 'Пещера');
    expect(poiCategoryLabel('island'), 'Остров');
    expect(poiCategoryLabel('city'), 'Город');
    expect(poiCategoryLabel('ruins'), 'Руины');
    expect(poiCategoryLabel('cape'), 'Мыс');
    expect(poiCategoryLabel('museum'), 'Музей');
    expect(poiCategoryLabel('fort'), 'Крепость');
  });

  test('poiCategoryLabel: фолбэк для пустой и неизвестной категории', () {
    expect(poiCategoryLabel(null), 'Место');
    expect(poiCategoryLabel('unknown-category'), 'Место');
    expect(poiCategoryLabel(''), 'Место');
  });

  test('poiCategoryGlyph отдаёт зарегистрированный ассет', () {
    // Глиф всегда существующий файл из assets/map_icons_flat.
    for (final id in [
      null,
      'bay',
      'beach',
      'church',
      'fort',
      'unknown',
    ]) {
      expect(poiCategoryGlyph(id), startsWith('assets/map_icons_flat/'));
      expect(poiCategoryGlyph(id), endsWith('.png'));
    }
  });

  test('kPoiCategories: глиф каждой категории = иконка её маркера', () {
    // Глиф — плоская копия иконки МАРКЕРА той же категории:
    // hero-плейсхолдер не расходится с картой (P0-8).
    for (final entry in kPoiCategories.entries) {
      final flat = entry.value.mapIcon ?? 'map-pin.png';
      expect(entry.value.glyph, 'assets/map_icons_flat/$flat',
          reason: 'глиф «${entry.key}» должен повторять иконку маркера');
    }
  });

  test('категории с иконкой карты дают poiCategoryMapIcon', () {
    // Раньше museum/tomb/square/book/aquarium получали map-pin в
    // плейсхолдере при осмысленном маркере на карте.
    expect(poiCategoryMapIcon('museum'), 'landmark.png');
    expect(poiCategoryMapIcon('tomb'), 'archway.png');
    expect(poiCategoryMapIcon('square'), 'monument.png');
    expect(poiCategoryMapIcon('book'), 'book-open.png');
    expect(poiCategoryMapIcon('aquarium'), 'fish.png');
    expect(poiCategoryGlyph('museum'), 'assets/map_icons_flat/landmark.png');

    // Категории без иконки на карте — булавка и в плейсхолдере.
    expect(poiCategoryMapIcon('tower'), isNull);
    expect(poiCategoryMapIcon('ruins'), isNull);
    expect(poiCategoryGlyph('ruins'), 'assets/map_icons_flat/map-pin.png');

    expect(poiCategoryMapIcon(null), isNull);
    expect(poiCategoryMapIcon('unknown'), isNull);
  });

  test('таблица покрывает все прежние названия', () {
    for (final id in [
      'anchor', 'church', 'cathedral', 'mosque', 'monastery',
      'water', 'cistern', 'lighthouse', 'viewpoint', 'tomb',
      'necropolis', 'cape', 'gallery', 'aquarium', 'university',
      'fort', 'peak', 'shrine', 'beach', 'railway', 'book',
      'museum', 'monument', 'tower', 'square', 'park', 'ski',
      'lake', 'entrance', 'street', 'village', 'valley', 'bay',
      'cave', 'island', 'city', 'ruins',
    ]) {
      expect(kPoiCategories.containsKey(id), isTrue, reason: id);
    }
  });
}
