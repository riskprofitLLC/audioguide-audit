import 'package:web/web.dart' as web;

/// Сдвиг верхней правой колонки контролов maplibre (компас +
/// атрибуция) вниз на web (13-й проход).
///
/// Плагин на web НЕ поддерживает compassViewMargins — правое
/// смещение колонки задаёт CSS (`.maplibregl-ctrl-top-right` в
/// web/index.html), а ВЕРХНИЙ сдвиг при подсветке ?poi=/?trail=
/// (controlsTopShift 52) передаётся CSS-переменной: иначе компас
/// перекрывался пилюлей «К описанию» на телефонах.
void applyMapControlsTopShift(double px) {
  // documentElement — Element без style: корень <html> —
  // HTMLElement, приводим (сеттер на корне действует глобально).
  final root = web.document.documentElement as web.HTMLElement?;

  root?.style.setProperty(
    '--map-ctrl-top-shift',
    '${px.round()}px',
  );
}
