// Баг 16 (замечания Sonnet): оценка времени прохождения маршрута.
//
// Пешком — прежние 4 км/ч; «на воде» — скорость манифеста
// (boatSpeedKmh, дефолт 8 км/ч), а не пешеходные 4 км/ч.

import 'package:flutter_test/flutter_test.dart';

import 'package:island_guide/core/utils/travel_time.dart';

void main() {
  group('travelTimeLabel', () {
    test('пешком — 4 км/ч (регрессия B2.3)', () {
      // 4 км пешком = 1 час.
      expect(travelTimeLabel(4000), '1 ч');

      // 2 км = 30 минут.
      expect(travelTimeLabel(2000), '30 мин');

      // 5,33 км ≈ 1 ч 20 мин.
      expect(travelTimeLabel(5333), '1 ч 20 мин');
    });

    test('на воде — 8 км/ч по умолчанию, а не пешеходные 4', () {
      // 8 км на воде = 1 час; пешеходная оценка дала бы 2 часа.
      expect(travelTimeLabel(8000, isBoat: true), '1 ч');

      // 4 км на воде = 30 минут; пешеходная — 1 час.
      expect(travelTimeLabel(4000, isBoat: true), '30 мин');
    });

    test('скорость лодки — из манифеста (boatSpeedKmh)', () {
      // 12 км при 12 км/ч = 1 час.
      expect(travelTimeLabel(12000, isBoat: true, boatSpeedKmh: 12), '1 ч');

      // 6 км при 12 км/ч = 30 минут.
      expect(travelTimeLabel(6000, isBoat: true, boatSpeedKmh: 12), '30 мин');
    });
  });
}
