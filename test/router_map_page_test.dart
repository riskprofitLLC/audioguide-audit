// Тест сборки страницы `/map` из query-параметров глубокой ссылки.
//
// Мусорный `?island=` (локация удалена из каталога, опечатка)
// не должен попадать в MapPage: иначе контентные провайдеры
// падают на regionOfLocation (StateError), и карта показывает
// «Не удалось загрузить стиль карты» вместо карты.

import 'package:flutter_test/flutter_test.dart';

import 'package:island_guide/app/router.dart';

void main() {
  group('buildMapPageFromQueryParameters', () {
    test('валидная локация проходит как есть', () {
      final page = buildMapPageFromQueryParameters({
        'island': 'gemiler',
      });

      expect(page.islandId, 'gemiler');
    });

    test('мусорный island отбрасывается (karacaoren удалён)', () {
      final page = buildMapPageFromQueryParameters({
        'island': 'karacaoren',
      });

      // Неизвестный id не должен дойти до контентных провайдеров:
      // раньше ронял карту StateError'ом в regionOfLocation.
      expect(page.islandId, isNull);
    });

    test('несуществующий island отбрасывается', () {
      final page = buildMapPageFromQueryParameters({
        'island': 'no-such-island',
      });

      expect(page.islandId, isNull);
    });

    test('отсутствующий island — null', () {
      final page = buildMapPageFromQueryParameters({});

      expect(page.islandId, isNull);
    });

    test('координаты камеры и выделения разбираются', () {
      final page = buildMapPageFromQueryParameters({
        'lat': '36.55',
        'lng': '29.07',
        'zoom': '15.5',
        'island': 'bay',
        'trail': 'trail-01',
        'poi': 'poi-03',
      });

      expect(page.lat, 36.55);
      expect(page.lng, 29.07);
      expect(page.zoom, 15.5);
      expect(page.islandId, 'bay');
      expect(page.highlightTrailId, 'trail-01');
      expect(page.highlightPoiId, 'poi-03');
    });

    test('нечисловые координаты отбрасываются', () {
      final page = buildMapPageFromQueryParameters({
        'lat': 'мусор',
        'lng': '',
      });

      expect(page.lat, isNull);
      expect(page.lng, isNull);
    });
  });
}
