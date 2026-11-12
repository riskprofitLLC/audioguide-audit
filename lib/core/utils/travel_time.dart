/// Оценка времени прохождения маршрута из его длины (баг 16,
/// замечания Sonnet).
///
/// Пешком — 4 км/ч (B2.3). «На воде» — скорость из манифеста
/// локации `boatSpeedKmh` (дефолт 8 км/ч): прежняя оценка делила
/// морской маршрут на пешеходные 4 км/ч и занижала время вдвое.
/// Формат: «20 мин», «1 ч», «1 ч 20 мин».
String travelTimeLabel(
  double meters, {
  bool isBoat = false,
  double boatSpeedKmh = 8.0,
}) {
  final speedKmh = isBoat ? boatSpeedKmh : 4.0;

  final minutes = (meters / (speedKmh * 1000) * 60).round();

  if (minutes < 60) {
    return '$minutes мин';
  }

  final hours = minutes ~/ 60;

  final rest = minutes % 60;

  return rest == 0 ? '$hours ч' : '$hours ч $rest мин';
}
