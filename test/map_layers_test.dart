// Тест чистой функции построения match-выражения иконок POI
// (map_layers.dart, buildPoiIconImageExpression).

import 'package:flutter_test/flutter_test.dart';

import 'package:island_guide/features/map/presentation/widgets/map_widget.dart';
import 'package:island_guide/features/map/utils/poi_category_filter.dart';
import 'package:island_guide/features/poi/models/poi.dart';

void main() {
  const iconAssets = {
    'anchor': 'anchor.png',
    'church': 'church.png',
    'beach': 'umbrella-beach.png',
  };

  group('buildPoiIconImageExpression', () {
    test('известные категории получают свои иконки + фолбэк', () {
      final expression = buildPoiIconImageExpression(
        {'anchor', 'beach'},
        iconAssets,
        defaultIcon: 'poi-default',
      ) as List<dynamic>;

      expect(expression, [
        'match',
        ['get', 'category'],
        'anchor',
        'poi-anchor',
        'beach',
        'poi-beach',
        'poi-default',
      ]);
    });

    test('порядок пар — по карте иконок, а не по множеству', () {
      final expression = buildPoiIconImageExpression(
        {'beach', 'anchor'},
        iconAssets,
        defaultIcon: 'poi-default',
      ) as List<dynamic>;

      expect(
        expression.sublist(2),
        ['anchor', 'poi-anchor', 'beach', 'poi-beach', 'poi-default'],
      );
    });

    test('ни одна категория не известна — просто иконка-фолбэк', () {
      // Кария: категории bay/cave/island/city/ruins не имеют
      // своих SDF-иконок. Вырожденный `['match', input, default]`
      // невалиден (match без пар) и ронял слой иконок целиком.
      final expression = buildPoiIconImageExpression(
        {'bay', 'cave', 'island', 'city', 'ruins'},
        iconAssets,
        defaultIcon: 'poi-default',
      );

      expect(expression, 'poi-default');
    });

    test('пустое множество категорий — иконка-фолбэк', () {
      final expression = buildPoiIconImageExpression(
        const {},
        iconAssets,
        defaultIcon: 'poi-default',
      );

      expect(expression, 'poi-default');
    });

    test('неиспользуемые категории в выражение не попадают', () {
      final expression = buildPoiIconImageExpression(
        {'church'},
        iconAssets,
        defaultIcon: 'poi-default',
      ) as List<dynamic>;

      expect(expression, [
        'match',
        ['get', 'category'],
        'church',
        'poi-church',
        'poi-default',
      ]);
    });
  });

  group('прослушанные маркеры (1b)', () {
    test('цвет шарика: избранное > прослушанное > категория', () {
      final expression = buildPoiBallColorExpression('#1668A8')
          as List<dynamic>;

      expect(expression, [
        'case',
        ['get', 'isFavorite'],
        '#E85D3F',
        ['get', 'isListened'],
        '#CFC7B2',
        '#1668A8',
      ]);
    });

    test('прозрачность иконки: прослушанные приглушены', () {
      final expression = buildPoiIconOpacityExpression() as List<dynamic>;

      expect(expression, [
        'case',
        ['get', 'isListened'],
        0.55,
        1.0,
      ]);
    });
  });

  group('фильтр категорий (1c)', () {
    final pois = [
      const Poi(
        id: 'poi-01',
        title: 'Церковь',
        latitude: 36.5,
        longitude: 29.0,
        category: 'church',
      ),
      const Poi(
        id: 'poi-02',
        title: 'Пляж',
        latitude: 36.5,
        longitude: 29.1,
        category: 'beach',
      ),
    ];

    test('null — все точки, списки те же', () {
      final result = filterPoisByCategory(pois, ['a', 'b'], null);

      expect(result.pois.length, 2);
      expect(result.locations, ['a', 'b']);
    });

    test('категория — только её точки, соответствие сохранено', () {
      final result = filterPoisByCategory(pois, ['a', 'b'], 'beach');

      expect(result.pois.map((p) => p.id), ['poi-02']);
      expect(result.locations, ['b']);
    });

    test('нет совпадений — пустая выдача', () {
      final result = filterPoisByCategory(pois, ['a', 'b'], 'fort');

      expect(result.pois, isEmpty);
      expect(result.locations, isEmpty);
    });
  });
}
