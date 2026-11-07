// Тесты геометрических расчётов (дистанция по гаверсинусам).

import 'package:flutter_test/flutter_test.dart';

import 'package:island_guide/features/gps/services/location_service.dart';

void main() {
  group('LocationService.distanceMeters', () {

    test('нулевая дистанция между одинаковыми точками', () {

      final distance = LocationService.distanceMeters(
        43.0, 131.9,
        43.0, 131.9,
      );

      expect(distance, lessThan(1));
    });

    test('один градус широты ≈ 111 км', () {

      final distance = LocationService.distanceMeters(
        43.0, 131.9,
        44.0, 131.9,
      );

      expect(distance, closeTo(111190, 500));
    });

    test('километр на широте ~43°', () {

      final distance = LocationService.distanceMeters(
        43.0142866, 131.930279,
        43.0142866, 131.9428,
      );

      expect(distance, greaterThan(900));
      expect(distance, lessThan(1100));
    });

    test('перестановка точек не меняет дистанцию', () {

      final a = LocationService.distanceMeters(
        42.9, 131.8,
        43.05, 131.95,
      );

      final b = LocationService.distanceMeters(
        43.05, 131.95,
        42.9, 131.8,
      );

      expect(a, closeTo(b, 0.01));
    });
  });
}
