/// Форматирование длины маршрута для UI.
///
/// Одна функция вместо дублей в карточке маршрута на главной
/// и на странице маршрута (`trail_detail_page.dart`).
///
/// Локаль (B14): русская десятичная запятая («3,1 км») и
/// неразрывный пробел между числом и единицей — строка не
/// рвётся переносом.
library;

String formatTrailDistance(double? distance) {

  if (distance == null) {
    return 'Длина неизвестна';
  }

  if (distance < 1000) {
    return '${distance.toStringAsFixed(0)}\u00A0м';
  }

  final km = (distance / 1000).toStringAsFixed(1).replaceAll('.', ',');

  return '$km\u00A0км';
}
