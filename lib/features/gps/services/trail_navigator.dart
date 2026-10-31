import 'dart:math';

import '../../../core/utils/geo_angles.dart';
import '../../trails/models/trail.dart';
import '../../trails/models/trail_point.dart';
import '../models/user_position.dart';
import 'location_service.dart';

/// Состояние навигации по маршруту.
class TrailNavigationState {

  const TrailNavigationState({
    required this.trail,
    required this.distanceToTrack,
    required this.offRoute,
    required this.bearing,
    this.reversed = false,
    this.maneuver,
  });


  /// Активный маршрут (ближайший к пользователю).
  final Trail trail;


  /// Расстояние до линии маршрута (метры).
  final double distanceToTrack;


  /// Пользователь отклонился от маршрута.
  final bool offRoute;


  /// Азимут на следующую точку маршрута (градусы 0..360).
  final double bearing;


  /// Пользователь идёт ПРОТИВ порядка вершин (A17, 17-й проход):
  /// азимут уже инвертирован к «следующей для него» точке.
  final bool reversed;


  /// Ближайший манёвр по маршруту (29-й проход, П4): следующая
  /// вершина с поворотом — «через N м направо». null — рядом нет
  /// вершины (пустой маршрут).
  final TrailManeuver? maneuver;
}


/// Ближайший манёвр (поворот) на маршруте (29-й проход, П4).
class TrailManeuver {

  const TrailManeuver({
    required this.distanceMeters,
    required this.turnDegrees,
    required this.isFinish,
  });


  /// Расстояние от текущей проекции на маршрут до вершины манёвра.
  final double distanceMeters;


  /// Угол поворота на вершине: положительный — направо
  /// (по часовой), отрицательный — налево, модуль 0..180.
  final double turnDegrees;


  /// Вершина — конечная точка маршрута (следующей вершины нет).
  final bool isFinish;


  /// Словесная инструкция: «прямо», «направо», «налево», «разворот».
  String get instruction {
    if (isFinish) {
      return 'финиш';
    }

    final angle = turnDegrees.abs();

    if (angle < 25) {
      return 'прямо';
    }

    if (angle > 140) {
      return 'разворот';
    }

    return turnDegrees > 0 ? 'направо' : 'налево';
  }
}


/// Ближайшая точка на линии маршрута.
class NearestTrackPoint {

  NearestTrackPoint({
    required this.trail,
    required this.latitude,
    required this.longitude,
    required this.distanceToTrack,
    required this.bearing,
    required this.behindBearing,
    this.segmentBranch,
    this.segmentIndex,
  });


  final Trail trail;


  /// Проекция позиции пользователя на линию маршрута.
  final double latitude;


  final double longitude;


  final double distanceToTrack;


  /// Азимут от проекции на следующую вершину маршрута (порядок).
  final double bearing;


  /// Азимут от проекции на предыдущую вершину — «вперёд» для
  /// идущего навстречу порядку (гистерезис в TrailNavigator.update,
  /// A5, 18-й проход).
  final double behindBearing;


  /// Ветка и индекс ближайшего сегмента (29-й проход, П4): по ним
  /// строится манёвр — следующая вершина в направлении движения.
  final List<TrailPoint>? segmentBranch;

  final int? segmentIndex;
}


/// Навигатор по треку.
///
/// Чистая логика: по позиции пользователя и списку маршрутов
/// определяет ближайший маршрут, расстояние до его линии,
/// отклонение (off-route) и направление движения.
class TrailNavigator {

  TrailNavigator({
    this.offRouteThresholdMeters = 30,
  });


  /// Порог отклонения от маршрута (метры).
  final double offRouteThresholdMeters;


  /// Гистерезис разворота (A5, 18-й проход): «вперёд» ↔ «назад»
  /// переключаются с запасом — у жёсткой границы 90° курс
  /// дребезжал и подсказка мерцала «Идти…» ↔ «Идти назад…».
  ///
  /// Вход в «назад» — расхождение больше 110°, возврат к
  /// «вперёд» — меньше 70°; между порогами сохраняется прежнее
  /// решение (инерция).
  static const double _reverseEnterDegrees = 110;

  static const double _reverseExitDegrees = 70;


  /// Для какого маршрута сейчас активен «назад» (состояние
  /// гистерезиса живёт между тиками).
  String? _reversedTrailId;

  /// Текущее решение «идёт навстречу порядку вершин».
  bool _reversed = false;


  /// Вычисляет состояние навигации по текущей позиции.
  ///
  /// [course] — фактический курс пользователя (градусы, 0 —
  /// север): по нему «следующая» точка перевыбирается, когда
  /// человек идёт против порядка вершин (A17, 17-й проход).
  /// `null` — курс неизвестен, подсказка ведёт по порядку.
  ///
  /// Возвращает `null`, если маршрутов нет или они пустые.
  TrailNavigationState? update(
    UserPosition position,
    List<Trail> trails, {
    double? course,
  }) {

    // Логов нет сознательно: метод вызывается на каждый GPS-тик
    // (см. trail_navigator_benchmark_test.dart) — интерполяция
    // строк и map/toList здесь лишние аллокации в горячем пути.
    NearestTrackPoint? best;

    for (final trail in trails) {

      final nearest = nearestTrackPoint(
        position,
        trail,
      );

      if (nearest == null) {

        continue;
      }

      if (best == null ||
          nearest.distanceToTrack < best.distanceToTrack) {

        best = nearest;
      }
    }

    if (best == null) {

      return null;
    }

    // Гистерезис разворота (A5, 18-й проход): решение меняется
    // только за пределами мёртвой зоны 70–110°. Курс пропал
    // (стоящий пользователь — MapWidget подаёт только свежий
    // курс) — сохраняем прежнее направление, подсказка не мигает.
    var reversed =
        _reversed && _reversedTrailId == best.trail.id;

    if (course != null) {

      final diff = angleBetween(course, best.bearing);

      if (!reversed && diff > _reverseEnterDegrees) {

        reversed = true;

      } else if (reversed && diff < _reverseExitDegrees) {

        reversed = false;
      }
    }

    _reversedTrailId = best.trail.id;

    _reversed = reversed;

    // Манёвр считаем в направлении движения (П4, 29-й проход):
    // при «назад» — к предыдущей вершине сегмента.
    final maneuver = nextManeuver(
      position,
      best,
      reversed: reversed,
    );

    return TrailNavigationState(
      trail: best.trail,
      distanceToTrack: best.distanceToTrack,
      offRoute: best.distanceToTrack > offRouteThresholdMeters,
      bearing: reversed ? best.behindBearing : best.bearing,
      reversed: reversed,
      maneuver: maneuver,
    );
  }


  /// Ближайшая точка на линии одного маршрута.
  ///
  /// Проецирует позицию на каждый сегмент и выбирает
  /// минимальное расстояние. Ветки маршрута ([Trail.segments])
  /// НЕ соединяются: фиктивный сегмент «конец одной ветки →
  /// начало другой» — не путь, и расстояние до него не должно
  /// засчитываться.
  NearestTrackPoint? nearestTrackPoint(
    UserPosition position,
    Trail trail,
  ) {

    final segments = trail.segments;

    double? minDistance;

    // Вершина, на которую указывает азимут по порядку ветки
    // (следующая вершина ближайшего сегмента).
    TrailPoint? aheadPoint;

    // Вершина позади по порядку — «следующая» при движении
    // навстречу порядку вершин (A17).
    TrailPoint? behindPoint;

    // Ближайший сегмент (29-й проход, П4): нужен для манёвра.
    List<TrailPoint>? bestBranch;

    var bestIndex = 0;

    var projectedLat = 0.0;

    var projectedLon = 0.0;

    for (final branch in segments) {

      for (var i = 0; i < branch.length - 1; i++) {

        final projection = _projectPointToSegment(
          position,
          branch[i],
          branch[i + 1],
        );

        if (minDistance == null ||
            projection.distance < minDistance) {

          minDistance = projection.distance;

          aheadPoint = branch[i + 1];

          behindPoint = branch[i];

          bestBranch = branch;

          bestIndex = i;

          projectedLat = projection.latitude;

          projectedLon = projection.longitude;
        }
      }
    }

    if (minDistance == null || aheadPoint == null) {

      return null;
    }

    // Направление по маршруту — к следующей вершине сегмента.
    // Для любого сегмента [i, i+1] она существует, в том числе
    // на последнем сегменте ветки (это её конечная точка).
    final aheadBearing = LocationService.bearingDegrees(
      projectedLat,
      projectedLon,
      aheadPoint.latitude,
      aheadPoint.longitude,
    );

    // Азимут к ПРЕДЫДУЩЕЙ вершине — «вперёд» для идущего навстречу
    // порядку (выбирается в update по гистерезису, A5 18-го).
    final behindBearing = behindPoint == null
        ? aheadBearing
        : LocationService.bearingDegrees(
            projectedLat,
            projectedLon,
            behindPoint.latitude,
            behindPoint.longitude,
          );

    return NearestTrackPoint(
      trail: trail,
      latitude: projectedLat,
      longitude: projectedLon,
      distanceToTrack: minDistance,
      bearing: aheadBearing,
      behindBearing: behindBearing,
      segmentBranch: bestBranch,
      segmentIndex: bestIndex,
    );
  }


  /// Ближайший манёвр на маршруте (29-й проход, П4).
  ///
  /// [nearest] — результат [nearestTrackPoint]; [reversed] —
  /// направление движения (навстречу порядку вершин — манёвр
  /// считается к предыдущей вершине сегмента).
  TrailManeuver? nextManeuver(
    UserPosition position,
    NearestTrackPoint nearest, {
    required bool reversed,
  }) {
    final branch = nearest.segmentBranch;

    final index = nearest.segmentIndex;

    if (branch == null || index == null || branch.length < 2) {
      return null;
    }

    // Вершина манёвра в направлении движения и следующая за ней.
    final vertex = reversed ? branch[index] : branch[index + 1];

    final nextIndex = reversed ? index - 1 : index + 2;

    final distance = LocationService.distanceMeters(
      nearest.latitude,
      nearest.longitude,
      vertex.latitude,
      vertex.longitude,
    );

    if (nextIndex < 0 || nextIndex >= branch.length) {
      // Конец ветки — финиш маршрута.
      return TrailManeuver(
        distanceMeters: distance,
        turnDegrees: 0,
        isFinish: true,
      );
    }

    final following = branch[nextIndex];

    // Подписанный угол поворота на вершине: азимут «к вершине»
    // минус азимут «от вершины дальше», по часовой положительный
    // (направо).
    final inBearing = LocationService.bearingDegrees(
      nearest.latitude,
      nearest.longitude,
      vertex.latitude,
      vertex.longitude,
    );

    final outBearing = LocationService.bearingDegrees(
      vertex.latitude,
      vertex.longitude,
      following.latitude,
      following.longitude,
    );

    var turn = outBearing - inBearing;

    if (turn > 180) {
      turn -= 360;
    } else if (turn < -180) {
      turn += 360;
    }

    return TrailManeuver(
      distanceMeters: distance,
      turnDegrees: turn,
      isFinish: false,
    );
  }



  /// Проекция точки на отрезок (в локальной равнопромежуточной
  /// проекции) и расстояние от точки до отрезка в метрах.
  ProjectionResult _projectPointToSegment(
    UserPosition position,
    TrailPoint a,
    TrailPoint b,
  ) {

    final cosLat = cos(
      _toRadians(position.latitude),
    );

    // Локальные координаты в метрах (ось X — на восток).
    final px = position.longitude * cosLat;

    final py = position.latitude;

    final ax = a.longitude * cosLat;

    final ay = a.latitude;

    final bx = b.longitude * cosLat;

    final by = b.latitude;

    final abx = bx - ax;

    final aby = by - ay;

    final apx = px - ax;

    final apy = py - ay;

    final abLength2 = abx * abx + aby * aby;

    final t = abLength2 == 0
        ? 0.0
        : (apx * abx + apy * aby) / abLength2;

    final clampedT = t.clamp(0.0, 1.0);

    final projLon = (ax + clampedT * abx) / cosLat;

    final projLat = ay + clampedT * aby;

    final distance = LocationService.distanceMeters(
      position.latitude,
      position.longitude,
      projLat,
      projLon,
    );

    return ProjectionResult(
      latitude: projLat,
      longitude: projLon,
      distance: distance,
    );
  }


  static double _toRadians(double degrees) {

    return degrees * pi / 180;
  }
}


class ProjectionResult {

  const ProjectionResult({
    required this.latitude,
    required this.longitude,
    required this.distance,
  });


  final double latitude;


  final double longitude;


  final double distance;
}
