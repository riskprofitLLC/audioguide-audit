/// Контроллер слежения за камерой (D5/R1 аудита Sonnet): чистая
/// логика режимов «следую за мной» и «по курсу» БЕЗ BuildContext —
/// вынесена из MapWidget в тестируемый класс.
///
/// Состояние: [following] (карта держит пользователя в центре),
/// [courseUp] (bearing камеры = курсу), [lastFollowTarget] (куда
/// последний раз подводили камеру). Внешние эффекты (setState,
/// анонсы скринридеру, animateCamera) остаются в виджете.
library;

import 'package:maplibre_gl/maplibre_gl.dart';

import '../../../core/utils/geo_angles.dart';
import '../../gps/services/location_service.dart';

/// Порог дрейфа в метрах: ручное панорамирование роняет слежение.
/// (Раньше жил в map_tracking.dart — регрессионные тесты остались
/// на forwarding-функции в map_widget.dart.)
const double kFollowDropDriftMeters = 40;

/// Предикат сброса слежения по дрейфу (Б7, 19-й проход).
bool shouldDropFollowing(double driftMeters) {
  return driftMeters > kFollowDropDriftMeters;
}

class FollowCameraController {

  /// Режим слежения включён.
  bool following = false;

  /// Режим «карта по курсу» (третий тап по кнопке GPS).
  bool courseUp = false;

  /// Последняя цель, куда слежение подводило камеру.
  LatLng? lastFollowTarget;

  /// Поколение собственной анимации камеры: пока > 0, дрейф
  /// не оценивается (Б7: во время полёта камеры она «опережает» цель).
  int _ownMoveGeneration = 0;

  /// Последний bearing, выставленный режимом course-up.
  double? _courseUpBearing;

  /// Идёт наша собственная анимация камеры — дрейф не оцениваем.
  bool get driftEvaluationSuspended => _ownMoveGeneration > 0;

  /// Начало собственного полёта камеры; вернуть поколение в
  /// [endOwnCameraMove] после завершения анимации.
  int beginOwnCameraMove() => ++_ownMoveGeneration;

  /// Конец собственного полёта камеры (или прерывание).
  void endOwnCameraMove(int generation) {
    if (_ownMoveGeneration == generation) {
      _ownMoveGeneration = 0;
    }
  }

  /// Оценка дрейфа камеры от цели слежения: true — пользователь
  /// панорамировал вручную, слежение надо сбросить.
  bool shouldDropForDrift(LatLng cameraTarget) {
    if (!following || driftEvaluationSuspended) {
      return false;
    }

    final target = lastFollowTarget;

    if (target == null) {
      return false;
    }

    final drift = LocationService.distanceMeters(
      cameraTarget.latitude,
      cameraTarget.longitude,
      target.latitude,
      target.longitude,
    );

    return shouldDropFollowing(drift);
  }

  /// Включение/выключение слежения. Возвращает true, если состояние
  /// изменилось (виджет тогда перестраивается и анонсирует).
  /// Выключение сбрасывает цель и режим «по курсу».
  bool setFollowing(bool value) {
    if (following == value) {
      return false;
    }

    following = value;

    if (!value) {
      lastFollowTarget = null;
      courseUp = false;
      _courseUpBearing = null;
    }

    return true;
  }

  /// Включить «карту по курсу».
  void enterCourseUp() {
    courseUp = true;
  }

  /// Выключить «карту по курсу».
  void exitCourseUp() {
    courseUp = false;
    _courseUpBearing = null;
  }

  /// Троттлинг поворотов course-up (≥10°): true — надо повернуть
  /// камеру на [course], false — поворот не нужен.
  bool shouldRotateCourseUp(double? course) {
    if (course == null) {
      return false;
    }

    final last = _courseUpBearing;

    if (last != null && anglesWithin(course, last, 10)) {
      return false;
    }

    _courseUpBearing = course;

    return true;
  }
}
