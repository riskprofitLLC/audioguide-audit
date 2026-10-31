// A15 (17-й проход): чип ближайшей точки при активном фильтре
// категорий.
//
// Решение: ближайшей считается ВИДИМАЯ точка — чип не должен
// предлагать объект, спрятанный фильтром (иначе карта «летит» к
// точке, которой на ней нет).

import 'package:flutter_test/flutter_test.dart';

import 'package:island_guide/features/gps/models/user_position.dart';
import 'package:island_guide/features/map/utils/poi_category_filter.dart';
import 'package:island_guide/features/poi/models/poi.dart';

Poi _poi(
  String id,
  String category, {
  double lat = 36.5548,
  double lng = 29.0658,
}) {
  return Poi(
    id: id,
    title: 'Точка $id',
    latitude: lat,
    longitude: lng,
    category: category,
  );
}

void main() {
  // Пользователь стоит на (36.5548, 29.0658): церковь на ~200 м
  // севернее, пляж на ~400 м севернее.
  final pois = [
    _poi('poi-01', 'church', lat: 36.5566),
    _poi('poi-02', 'beach', lat: 36.5584),
  ];

  const locations = ['gemiler', 'gemiler'];

  const position = UserPosition(latitude: 36.5548, longitude: 29.0658);

  group('nearestVisiblePoi (A15)', () {
    test('без фильтра ближайшая — церковь', () {

      final match = nearestVisiblePoi(
        position: position,
        pois: pois,
        locations: locations,
      );

      expect(match, isNotNull);
      expect(match!.poi.id, 'poi-01');
      expect(match.locationId, 'gemiler');
      expect(match.distance, inExclusiveRange(150, 250));
      // Точка почти ровно на север — азимут у нуля/360.
      expect(match.bearing % 360, lessThan(2));
    });

    test('фильтр «пляж» ведёт к ВИДИМОЙ точке, не к ближайшей', () {

      final match = nearestVisiblePoi(
        position: position,
        pois: pois,
        locations: locations,
        category: 'beach',
      );

      expect(match, isNotNull);

      // Церковь ближе, но фильтр её прячет — чип зовёт на пляж.
      expect(match!.poi.id, 'poi-02');

      expect(match.distance, inExclusiveRange(350, 450));
    });

    test('фильтр без совпадений — кандидатов нет', () {

      final match = nearestVisiblePoi(
        position: position,
        pois: pois,
        locations: locations,
        category: 'lighthouse',
      );

      expect(match, isNull);
    });

    test('пустой список точек — null', () {

      expect(
        nearestVisiblePoi(
          position: position,
          pois: const [],
          locations: const [],
        ),
        isNull,
      );
    });

    test('локация параллельного списка сохраняется (id повторяются)', () {

      final multi = [
        _poi('poi-01', 'beach', lat: 36.5566),
        _poi('poi-01', 'beach', lat: 36.5584),
      ];

      final match = nearestVisiblePoi(
        position: position,
        pois: multi,
        locations: ['bay', 'kekova'],
      );

      expect(match!.locationId, 'bay');
    });
  });
}
