import '../../gps/services/location_service.dart';
import '../../poi/models/poi.dart';
import '../../trails/utils/format_distance.dart';

/// План дня из набора точек (29-й проход, П9).
///
/// Чистая логика: порядок точек — как в подборке (или
/// оптимизированный, [optimizeStopOrder]); между соседними
/// точками — дистанция (haversine) и время: пешком 4 км/ч, на
/// воде — скорость локации (`boatSpeedKmh`, манифест Кековы),
/// плюс длительность аудиогида каждой точки.

/// Один шаг плана: точка + способ добраться до неё.
class DayPlanStop {
  const DayPlanStop({
    required this.locationId,
    required this.poi,
    this.isBoat = false,
    this.speedKmh = 8.0,
  });

  /// Локация точки — нужна для перехода в детали из плана.
  final String locationId;

  final Poi poi;

  /// Локация с `transport: "boat"` (Кекова): между точками —
  /// вода, пешая оценка занижала бы время вдвое.
  final bool isBoat;

  /// Скорость на воде из манифеста локации.
  final double speedKmh;
}

/// Один шаг плана: точка + путь до неё от предыдущей.
class DayPlanLeg {
  const DayPlanLeg({
    required this.poi,
    required this.travelMeters,
    required this.travelMinutes,
    required this.audioMinutes,
    required this.isBoat,
  });

  final Poi poi;

  /// Расстояние от предыдущей точки плана (0 для первой).
  final double travelMeters;

  final int travelMinutes;

  /// Длительность аудиогида точки в минутах (0 — без аудио).
  final int audioMinutes;

  final bool isBoat;

  /// «1,2 км» / «340 м» — русская запятая, неразрывный пробел.
  String get distanceLabel => formatTrailDistance(travelMeters);
}

class DayPlan {
  const DayPlan({
    required this.legs,
    required this.travelMinutes,
    required this.audioMinutes,
  });

  final List<DayPlanLeg> legs;

  final int travelMinutes;

  final int audioMinutes;

  int get totalMinutes => travelMinutes + audioMinutes;

  double get totalMeters =>
      legs.fold(0.0, (sum, leg) => sum + leg.travelMeters);

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

/// Время суток → «14:30» (для старта и оценки финиша).
String formatClock(DateTime time) {
  final h = time.hour.toString().padLeft(2, '0');

  final m = time.minute.toString().padLeft(2, '0');

  return '$h:$m';
}

/// Суммарное пешее/водное время плана в минутах (для оценки
/// финиша и сравнения порядков).
int planTravelMinutes(List<DayPlanLeg> legs) =>
    legs.fold(0, (sum, leg) => sum + leg.travelMinutes);

/// Считает план дня по шагам в заданном порядке.
///
/// [start] — необязательная точка отправления («Вы здесь»):
/// путь до первой точки плана считается от неё.
DayPlan computeDayPlan(
  List<DayPlanStop> stops, {
  (double latitude, double longitude)? start,
}) {
  final legs = <DayPlanLeg>[];

  var travelMinutes = 0;

  // Аудио суммируется в МИЛЛИСЕКУНДАХ, а минуты считаются один
  // раз на итог: деление каждой точки теряло её «хвост» секунд
  // (3 точки по 6:30 давали 18 мин вместо 19).
  var audioMsTotal = 0;

  for (var i = 0; i < stops.length; i++) {
    final stop = stops[i];

    final from = i == 0
        ? start
        : (
            stops[i - 1].poi.latitude,
            stops[i - 1].poi.longitude,
          );

    final travelMeters = from == null
        ? 0.0
        : LocationService.distanceMeters(
            from.$1,
            from.$2,
            stop.poi.latitude,
            stop.poi.longitude,
          );

    // Пешком 4 км/ч — та же константа, что в travelTimeLabel; на
    // воде — скорость локации из манифеста.
    final speedKmh = stop.isBoat ? stop.speedKmh : 4.0;

    final legTravelMinutes = (travelMeters / (speedKmh * 1000) * 60).round();

    final legAudioMs = stop.poi.audioMs ?? 0;

    audioMsTotal += legAudioMs;

    travelMinutes += legTravelMinutes;

    legs.add(
      DayPlanLeg(
        poi: stop.poi,
        travelMeters: travelMeters,
        travelMinutes: legTravelMinutes,
        audioMinutes: (legAudioMs / 60000).round(),
        isBoat: stop.isBoat,
      ),
    );
  }

  return DayPlan(
    legs: legs,
    travelMinutes: travelMinutes,
    audioMinutes: (audioMsTotal / 60000).round(),
  );
}

/// Переставляет шаги, сокращая путь: ближайший сосед от старта +
/// 2-opt по полному пути. Возвращает перестановку индексов
/// [stops] — чистая функция, покрывается тестом без виджетов.
///
/// Первый шаг остаётся первым, если старт не задан: порядок
/// «от ворот отеля» обычно осмысленнее алфавитного.
List<int> optimizeStopOrder(
  List<DayPlanStop> stops, {
  (double latitude, double longitude)? start,
}) {
  if (stops.length < 3) {
    return List<int>.generate(stops.length, (i) => i);
  }

  // Ближайший сосед: стартуем от [start] или от первой точки.
  final remaining = List<int>.generate(stops.length, (i) => i);

  if (start == null) {
    remaining.removeAt(0);
  }

  final order = <int>[];

  // Без старта первая точка плана остаётся первой: порядок «от
  // ворот отеля» осмысленнее алфавитного.
  if (start == null) {
    order.add(0);
  }

  var current = start ??
      (
        stops.first.poi.latitude,
        stops.first.poi.longitude,
      );

  while (remaining.isNotEmpty) {
    var best = 0;

    var bestDistance = double.infinity;

    for (var i = 0; i < remaining.length; i++) {
      final poi = stops[remaining[i]].poi;

      final distance = LocationService.distanceMeters(
        current.$1,
        current.$2,
        poi.latitude,
        poi.longitude,
      );

      if (distance < bestDistance) {
        bestDistance = distance;

        best = i;
      }
    }

    final next = remaining.removeAt(best);

    order.add(next);

    current = (
      stops[next].poi.latitude,
      stops[next].poi.longitude,
    );
  }

  // 2-opt: переворот участков пути, пока он сокращает дистанцию.
  var improved = true;

  while (improved) {
    improved = false;

    for (var i = 0; i < order.length - 1; i++) {
      for (var j = i + 1; j < order.length; j++) {
        final candidate = _reversed(order, i, j);

        if (_pathMeters(stops, candidate, start) <
            _pathMeters(stops, order, start) - 1) {
          order
            ..clear()
            ..addAll(candidate);

          improved = true;
        }
      }
    }
  }

  return order;
}

List<int> _reversed(List<int> order, int i, int j) {
  final result = List<int>.of(order);

  var a = i;

  var b = j;

  while (a < b) {
    final tmp = result[a];

    result[a] = result[b];

    result[b] = tmp;

    a++;

    b--;
  }

  return result;
}

double _pathMeters(
  List<DayPlanStop> stops,
  List<int> order,
  (double latitude, double longitude)? start,
) {
  var total = 0.0;

  var previous = start ??
      (
        stops[order.first].poi.latitude,
        stops[order.first].poi.longitude,
      );

  for (final index in order) {
    final poi = stops[index].poi;

    total += LocationService.distanceMeters(
      previous.$1,
      previous.$2,
      poi.latitude,
      poi.longitude,
    );

    previous = (poi.latitude, poi.longitude);
  }

  return total;
}

/// Оценка времени финиша: старт + время плана.
DateTime estimateFinish(DateTime start, DayPlan plan) =>
    start.add(Duration(minutes: plan.totalMinutes));
