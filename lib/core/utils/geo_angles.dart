/// Реальный угол между двумя азимутами/компасными направлениями
/// (0–180°), с учётом перехода через север: 350° → 10° = 20°.
///
/// Единая реализация для карты (дребезг дистанции/поворотов,
/// троттлинг course-up, чип ближайшей точки) и навигатора по
/// маршруту (D2, замечания Sonnet — раньше три копии могли
/// разъезжаться).
double angleBetween(double a, double b) {
  final diff = (a - b).abs() % 360;

  return diff > 180 ? 360 - diff : diff;
}

/// Сравнение углов с допуском: |a − b| с переходом через север
/// меньше [toleranceDegrees].
bool anglesWithin(double a, double b, double toleranceDegrees) {
  return angleBetween(a, b) < toleranceDegrees;
}
