// Подлёт камеры к позиции пользователя (кнопка GPS).
//
// Регрессия 07.11.2026: подлёт спрашивал текущий зум через
// MapLibreMapController.queryCameraPosition(), а maplibre_gl_web этот
// метод НЕ реализует — бросает UnimplementedError. Ошибка глушилась
// catch'ом внутри _flyToPosition, поэтому на web камера не уходила к
// пользователю НИКОГДА: кнопка запоминала позицию и включала
// «следю за мной», но карта оставалась на прежнем месте. Со стороны
// пользователя «кнопка GPS не работает» — во всех браузерах, на
// Android и на iOS.
//
// Тесты фиксируют: зум считается из запомненного масштаба камеры,
// подлёт — один вызов анимации с центром в позиции пользователя, и
// падение анимации не роняет вызывающий код.

import 'package:flutter_test/flutter_test.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import 'package:island_guide/features/gps/models/user_position.dart';
import 'package:island_guide/features/map/services/locate_camera.dart';

void main() {
  group('locateZoomFor', () {
    test('камера ещё не двигалась — минимальный зум', () {
      expect(locateZoomFor(null), kLocateMinZoom);
    });

    test('дальний масштаб подтягиваем к минимальному', () {
      expect(locateZoomFor(9.4), kLocateMinZoom);
      expect(locateZoomFor(14.99), kLocateMinZoom);
    });

    test('ровно минимум — без изменений', () {
      expect(locateZoomFor(15), kLocateMinZoom);
    });

    test('пользователь приблизил сильнее — не отдаляем', () {
      expect(locateZoomFor(17.5), 17.5);
    });
  });

  group('flyCameraToPosition', () {
    const position = UserPosition(latitude: 36.551, longitude: 30.3505);

    test('один вызов анимации: центр в позиции, зум по масштабу камеры',
        () async {
      final updates = <CameraUpdate>[];

      await flyCameraToPosition(
        position,
        currentZoom: 12,
        animate: (update) async {
          updates.add(update);
          return true;
        },
      );

      expect(updates, hasLength(1));

      final json = updates.single.toJson() as List;

      // newLatLngBounds/scrollBy/zoomBy сюда попадать не должны:
      // подлёт к точке — это newLatLngZoom.
      expect(json.first, 'newLatLngZoom');

      // LatLng.toJson() — [latitude, longitude].
      final target = json[1] as List;
      expect(target[0], closeTo(position.latitude, 1e-9));
      expect(target[1], closeTo(position.longitude, 1e-9));

      expect(json[2], kLocateMinZoom);
    });

    test('собственный приближённый масштаб сохраняется', () async {
      final updates = <CameraUpdate>[];

      await flyCameraToPosition(
        position,
        currentZoom: 18,
        animate: (update) async {
          updates.add(update);
          return true;
        },
      );

      expect((updates.single.toJson() as List)[2], 18);
    });

    test('падение анимации не пробрасывается наружу', () async {
      // Ровно этот случай и был на web: queryCameraPosition бросал
      // UnimplementedError, подлёт умирал молча.
      await expectLater(
        flyCameraToPosition(
          position,
          currentZoom: 12,
          animate: (_) async => throw UnimplementedError(),
        ),
        completes,
      );
    });

    test('вызов анимации РОВНО один — зум не доспрашивается у карты',
        () async {
      // Регрессия: прежний код звал queryCameraPosition() ДО
      // animateCamera. На web это UnimplementedError, и анимация не
      // выполнялась вовсе. Теперь в путь подлёта нет никакого
      // запроса состояния камеры — только анимация.
      var calls = 0;

      await flyCameraToPosition(
        position,
        currentZoom: null,
        animate: (_) async {
          calls++;
          return true;
        },
      );

      expect(calls, 1);
    });
  });
}
