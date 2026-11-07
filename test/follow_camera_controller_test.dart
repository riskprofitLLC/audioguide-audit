// FollowCameraController (D5/R1): чистая логика слежения за камерой
// вынесена из MapWidget — юнит-тесты без виджетов.

import 'package:flutter_test/flutter_test.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import 'package:island_guide/features/map/controllers/follow_camera_controller.dart';

void main() {
  group('FollowCameraController', () {
    test('дрейф роняет слежение только вне собственной анимации и выше порога', () {
      final c = FollowCameraController()..setFollowing(true);

      c.lastFollowTarget = const LatLng(36.6, 29.1);

      // 20 м от цели — тихий шаг слежения, режим держится.
      expect(
        c.shouldDropForDrift(const LatLng(36.6001, 29.1)),
        isFalse,
      );

      // Во время собственной анимации дрейф не оценивается (Б7).
      final gen = c.beginOwnCameraMove();

      expect(
        c.shouldDropForDrift(const LatLng(36.61, 29.1)),
        isFalse,
        reason: 'своя анимация камеры — не жест пользователя',
      );

      c.endOwnCameraMove(gen);

      // >40 м от цели после анимации — ручное панорамирование.
      expect(
        c.shouldDropForDrift(const LatLng(36.61, 29.1)),
        isTrue,
      );
    });

    test('выключение слежения сбрасывает цель и course-up', () {
      final c = FollowCameraController()..setFollowing(true);

      c.lastFollowTarget = const LatLng(36.6, 29.1);

      c.enterCourseUp();

      expect(c.courseUp, isTrue);

      expect(c.setFollowing(false), isTrue);

      expect(c.following, isFalse);
      expect(c.lastFollowTarget, isNull);
      expect(c.courseUp, isFalse);

      // Повторное выключение — без изменения.
      expect(c.setFollowing(false), isFalse);
    });

    test('course-up троттлится по повороту ≥10°', () {
      final c = FollowCameraController();

      expect(c.shouldRotateCourseUp(null), isFalse);

      expect(c.shouldRotateCourseUp(50), isTrue);

      // 微ropоворot <10° — не поворачиваем.
      expect(c.shouldRotateCourseUp(55), isFalse);

      expect(c.shouldRotateCourseUp(61), isTrue);

      c.exitCourseUp();

      expect(c.shouldRotateCourseUp(200), isTrue,
          reason: 'после выхода из course-up порог сбрасывается');
    });
  });
}
