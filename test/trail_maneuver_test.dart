// П4 (29-й проход): ближайший манёвр по маршруту —
// «через N м направо/налево/финиш» в TrailNavigationState.

import 'package:flutter_test/flutter_test.dart';

import 'package:island_guide/features/gps/models/user_position.dart';
import 'package:island_guide/features/gps/services/trail_navigator.dart';
import 'package:island_guide/features/trails/models/trail.dart';
import 'package:island_guide/features/trails/models/trail_point.dart';

TrailPoint p(double lat, double lng, int order) =>
    TrailPoint(id: 'p$order', latitude: lat, longitude: lng, order: order);

/// Г-образный маршрут: на север 1,1 км, затем поворот на восток.
final lTrail = Trail(
  id: 'trail-01',
  name: 'Тестовый',
  points: [
    p(36.0000, 29.0000, 1),
    p(36.0100, 29.0000, 2),
    p(36.0100, 29.0200, 3),
  ],
);

void main() {
  group('манёвр (П4)', () {
    test('поворот направо: через ~1,1 км к вершине, азимут на восток', () {
      final nav = TrailNavigator();

      final state = nav.update(
        const UserPosition(latitude: 36.0000, longitude: 29.0000),
        [lTrail],
      );

      expect(state, isNotNull);

      final m = state!.maneuver;

      expect(m, isNotNull);

      expect(m!.isFinish, isFalse);

      // ~1112 м до вершины (0.01° широты).
      expect(m.distanceMeters, closeTo(1112, 30));

      expect(m.instruction, 'направо');

      expect(m.turnDegrees, closeTo(90, 5));
    });

    test('движение назад: манёвр считается к предыдущей вершине', () {
      final nav = TrailNavigator();

      // Стоим у восточного конца, курс на запад (против порядка).
      final state = nav.update(
        const UserPosition(latitude: 36.0100, longitude: 29.0190),
        [lTrail],
        course: 270,
      );

      expect(state, isNotNull);

      expect(state!.reversed, isTrue);

      final m = state.maneuver;

      expect(m, isNotNull);

      // До вершины поворота ~1,7 км (0.019° долготы на 36° широте).
      expect(m!.distanceMeters, closeTo(1709, 40));

      // С запада на юг — поворот налево.
      expect(m.instruction, 'налево');
    });

    test('конец маршрута: финиш на последней вершине', () {
      final nav = TrailNavigator();

      final twoPointTrail = Trail(
        id: 'trail-02',
        name: 'Короткий',
        points: [
          p(36.0000, 29.0000, 1),
          p(36.0100, 29.0000, 2),
        ],
      );

      final state = nav.update(
        const UserPosition(latitude: 36.0000, longitude: 29.0000),
        [twoPointTrail],
      );

      expect(state!.maneuver, isNotNull);

      expect(state.maneuver!.isFinish, isTrue);

      expect(state.maneuver!.instruction, 'финиш');
    });

    test('прямой участок без поворота — «прямо»', () {
      final nav = TrailNavigator();

      final straightTrail = Trail(
        id: 'trail-03',
        name: 'Прямой',
        points: [
          p(36.0000, 29.0000, 1),
          p(36.0100, 29.0000, 2),
          p(36.0200, 29.0000, 3),
        ],
      );

      final state = nav.update(
        const UserPosition(latitude: 36.0000, longitude: 29.0000),
        [straightTrail],
      );

      expect(state!.maneuver!.instruction, 'прямо');
    });
  });
}
