// Углы с переходом через север (D2, замечания Sonnet).
//
// Единая реализация для карты (дребезг дистанции, троттлинг
// course-up, чип ближайшей точки) и навигатора по маршруту:
// раньше было три копии, которые могли разъезжаться. Ошибка в
// переходе 350° → 10° тихая — компас/стрелки начинают «прыгать».

import 'package:flutter_test/flutter_test.dart';

import 'package:island_guide/core/utils/geo_angles.dart';

void main() {
  group('angleBetween', () {
    test('без перехода через север', () {
      expect(angleBetween(10, 40), 30);

      expect(angleBetween(40, 10), 30);
    });

    test('переход через север — короткая дуга', () {
      expect(angleBetween(350, 10), 20);

      expect(angleBetween(10, 350), 20);
    });

    test('противоположные направления — 180', () {
      expect(angleBetween(0, 180), 180);

      expect(angleBetween(90, 270), 180);
    });

    test('больше полного оборота — приводится по модулю', () {
      expect(angleBetween(370, 10), 0);

      expect(angleBetween(-10, 10), 20);
    });

    test('совпадающие направления — 0', () {
      expect(angleBetween(123, 123), 0);
    });
  });

  group('anglesWithin', () {
    test('внутри допуска, включая переход через север', () {
      expect(anglesWithin(350, 10, 25), isTrue);
    });

    test('на границе допуска — строго меньше', () {
      expect(anglesWithin(0, 20, 20), isFalse);

      expect(anglesWithin(0, 19.9, 20), isTrue);
    });

    test('вне допуска', () {
      expect(anglesWithin(0, 90, 25), isFalse);
    });
  });
}
