// Тесты детектора входа в радиус POI.

import 'package:flutter_test/flutter_test.dart';

import 'package:island_guide/features/gps/models/user_position.dart';
import 'package:island_guide/features/gps/services/poi_proximity_watcher.dart';
import 'package:island_guide/features/poi/models/poi.dart';

void main() {
  // Точка (43.0, 131.9) и POI на широте 43.01 при тех же
  // координатах — дистанция ровно 1.11 км (по широте).
  const lat1 = 43.0;
  const lon1 = 131.9;

  // POI с радиусом 250 м относительно точки (43.0, 131.9):
  // ~0.0015° широты = ~167 м.
  const poiLat = lat1 + 0.0015;

  Poi makePoi(String id, {double? radius}) {
    return Poi(
      id: id,
      title: id,
      latitude: poiLat,
      longitude: lon1,
      radius: radius ?? 250,
    );
  }

  group('PoiProximityWatcher', () {

    test('вход в радиус генерирует событие', () {

      final watcher = PoiProximityWatcher(
        pois: [makePoi('poi-1')],
      );

      final entered = watcher.update(
        const UserPosition(latitude: lat1, longitude: lon1),
      );

      expect(entered, hasLength(1));
      expect(entered.first.id, 'poi-1');
    });

    test('повторная позиция внутри радиуса не генерирует повтор', () {

      final watcher = PoiProximityWatcher(
        pois: [makePoi('poi-1')],
      );

      watcher.update(
        const UserPosition(latitude: lat1, longitude: lon1),
      );

      final again = watcher.update(
        const UserPosition(latitude: lat1, longitude: lon1),
      );

      expect(again, isEmpty);
    });

    test('повторное срабатывание после выхода из радиуса', () {

      final watcher = PoiProximityWatcher(
        pois: [makePoi('poi-1')],
      );

      watcher.update(
        const UserPosition(latitude: lat1, longitude: lon1),
      );

      // Уходим на 3 км к югу.
      watcher.update(
        const UserPosition(latitude: lat1 - 0.03, longitude: lon1),
      );

      // Возвращаемся — снова событие.
      final entered = watcher.update(
        const UserPosition(latitude: lat1, longitude: lon1),
      );

      expect(entered, hasLength(1));
    });

    test('не генерирует событие, если пользователь вне радиуса', () {

      final watcher = PoiProximityWatcher(
        pois: [makePoi('poi-1', radius: 100)],
      );

      final entered = watcher.update(
        const UserPosition(latitude: lat1 + 0.01, longitude: lon1),
      );

      expect(entered, isEmpty);
    });

    test('обрабатывает несколько POI независимо', () {

      final watcher = PoiProximityWatcher(
        pois: [
          makePoi('poi-1'),
          makePoi('poi-2', radius: 100),
        ],
      );

      final entered = watcher.update(
        const UserPosition(latitude: lat1, longitude: lon1),
      );

      expect(entered.map((p) => p.id), ['poi-1']);
    });

    test('POI без radius срабатывает с дефолтным радиусом 50 м', () {

      // Раньше null-радиус означал radius 0: точка не срабатывала
      // никогда, даже если пользователь стоял на ней.
      final watcher = PoiProximityWatcher(
        pois: [
          const Poi(
            id: 'poi-no-radius',
            title: 'poi-no-radius',
            latitude: poiLat,
            longitude: lon1,
          ),
        ],
      );

      // ~167 м — дальше дефолтных 50 м: события нет.
      final far = watcher.update(
        const UserPosition(latitude: lat1, longitude: lon1),
      );

      expect(far, isEmpty);

      // ~30 м (0.00027° широты) — внутри 50 м: событие есть.
      final near = watcher.update(
        const UserPosition(latitude: poiLat - 0.00027, longitude: lon1),
      );

      expect(near.map((p) => p.id), ['poi-no-radius']);
    });
  });
}
