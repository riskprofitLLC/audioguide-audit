import '../../gps/services/location_service.dart';
import '../../poi/models/poi.dart';

/// План дня из набора точек (29-й проход, П9).
///
/// Чистая логика: порядок точек — как в подборке; между соседними
/// точками — пешая дистанция (haversine) и время по 4 км/ч,
/// плюс длительность аудиогида каждой точки.

/// Один шаг плана: точка + путь до неё от предыдущей.
class DayPlanLeg {

  const DayPlanLeg({
    required this.poi,
    required this.walkMeters,
    required this.walkMinutes,
    required this.audioMinutes,
  });


  final Poi poi;

  /// Расстояние от предыдущей точки плана (0 для первой).
  final double walkMeters;

  final int walkMinutes;

  /// Длительность аудиогида точки в минутах (0 — без аудио).
  final int audioMinutes;
}


class DayPlan {

  const DayPlan({
    required this.legs,
    required this.walkMinutes,
    required this.audioMinutes,
  });


  final List<DayPlanLeg> legs;

  final int walkMinutes;

  final int audioMinutes;

  int get totalMinutes => walkMinutes + audioMinutes;

  /// «20 мин», «1 ч», «1 ч 20 мин» — как travelTimeLabel.
  String get totalLabel => formatMinutes(totalMinutes);
}


/// Минуты → «N мин» / «H ч» / «H ч M мин» (тот же формат, что в
/// travelTimeLabel, но от минут, а не от метров).
String formatMinutes(int minutes) {
  if (minutes < 60) {
    return '$minutes мин';
  }

  final hours = minutes ~/ 60;

  final rest = minutes % 60;

  return rest == 0 ? '$hours ч' : '$hours ч $rest мин';
}


/// Считает план дня по списку точек в заданном порядке.
DayPlan computeDayPlan(List<Poi> pois) {
  final legs = <DayPlanLeg>[];

  var walkMinutes = 0;

  var audioMinutes = 0;

  for (var i = 0; i < pois.length; i++) {
    final poi = pois[i];

    final walkMeters = i == 0
        ? 0.0
        : LocationService.distanceMeters(
            pois[i - 1].latitude,
            pois[i - 1].longitude,
            poi.latitude,
            poi.longitude,
          );

    // Пешком 4 км/ч — та же константа, что в travelTimeLabel.
    final legWalkMinutes = (walkMeters / 4000 * 60).round();

    final legAudioMinutes = (poi.audioMs ?? 0) ~/ 60000;

    walkMinutes += legWalkMinutes;

    audioMinutes += legAudioMinutes;

    legs.add(
      DayPlanLeg(
        poi: poi,
        walkMeters: walkMeters,
        walkMinutes: legWalkMinutes,
        audioMinutes: legAudioMinutes,
      ),
    );
  }

  return DayPlan(
    legs: legs,
    walkMinutes: walkMinutes,
    audioMinutes: audioMinutes,
  );
}
