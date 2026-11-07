// Тесты сглаживания линий маршрутов: Douglas-Peucker упрощение.

import 'package:flutter_test/flutter_test.dart';

import 'package:island_guide/features/map/presentation/widgets/map_widget.dart';
import 'package:island_guide/features/trails/models/trail_point.dart';

TrailPoint _pt(double lat, double lon) => TrailPoint(
      id: '',
      latitude: lat,
      longitude: lon,
      order: 0,
    );

void main() {
  group('simplifyTrailPoints', () {

    test('прямая линия схлопывается в две точки', () {

      final points = [
        _pt(43.0, 131.0),
        _pt(43.0001, 131.0),
        _pt(43.0002, 131.0),
        _pt(43.0003, 131.0),
        _pt(43.001, 131.0),
      ];

      final simplified = simplifyTrailPoints(
        points,
        toleranceMeters: 2.0,
      );

      expect(simplified, hasLength(2));
      expect(simplified.first.latitude, 43.0);
      expect(simplified.last.latitude, closeTo(43.001, 0.000001));
    });

    test('сильный излом сохраняется', () {

      final points = [
        _pt(43.0, 131.0),
        _pt(43.001, 131.0),
        _pt(43.001, 131.001), // угол в ~110 м
      ];

      final simplified = simplifyTrailPoints(
        points,
        toleranceMeters: 2.0,
      );

      // Излом не удаляется.
      expect(simplified, hasLength(3));
    });

    test('мало точек возвращаются как есть', () {

      final points = [_pt(43.0, 131.0), _pt(43.001, 131.0)];

      final simplified = simplifyTrailPoints(
        points,
        toleranceMeters: 2.0,
      );

      expect(simplified, hasLength(2));
    });

    test('50 000 точек прямой — без переполнения стека', () {

      // Раньше реализация была рекурсивной (глубина ~ числа точек):
      // длинный трек ронял бы карту StackOverflowError. Итеративный
      // Douglas-Peucker со стеком диапазонов не зависит от глубины.
      final points = List.generate(
        50000,
        (i) => _pt(43.0 + i * 0.000001, 131.0),
      );

      final simplified = simplifyTrailPoints(
        points,
        toleranceMeters: 2.0,
      );

      expect(simplified, hasLength(2));
      expect(simplified.first.latitude, 43.0);
      expect(simplified.last.latitude, closeTo(43.05, 0.001));
    });

    test('пила с крупными зубцами: все вершины сохраняются', () {

      // Зигзаг с шагом ~500 м — все углы за пределами допуска 2 м,
      // упрощение обязано оставить каждую вершину.
      final points = <TrailPoint>[];
      for (var i = 0; i < 200; i++) {
        points.add(_pt(43.0 + i * 0.005, 131.0 + (i.isEven ? 0.0 : 0.005)));
      }

      final simplified = simplifyTrailPoints(
        points,
        toleranceMeters: 2.0,
      );

      expect(simplified, hasLength(points.length));
    });
  });
}
