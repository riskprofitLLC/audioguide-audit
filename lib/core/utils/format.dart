/// Единые форматтеры длительности и чисел (пункты 8 замечаний
/// Sonnet): раньше пять копий «m:ss» (home, poi_detail, плеер,
/// sticky-панель, галерея) и своя десятичная запятая в погоде.
library;

/// «6:33» — человекочитаемая длительность из миллисекунд.
/// Минуты — полные (без остатка на час), секунды — с ведущим
/// нулём. Отрицательные значения и мусор — «0:00».
String formatDurationMs(int? ms) {
  if (ms == null || ms <= 0) {
    return '00:00';
  }

  return formatDuration(Duration(milliseconds: ms));
}

/// «6:33» — человекочитаемая длительность из [Duration].
/// Минуты — полные (трек длиннее часа покажет «62:05»),
/// дополняются нулём до двух разрядов («01:00», «06:33»).
/// Ноль и отрицательное — «00:00».
String formatDuration(Duration d) {
  if (d <= Duration.zero) {
    return '00:00';
  }

  final totalSeconds = d.inSeconds;

  final minutes = (totalSeconds ~/ 60).toString().padLeft(2, '0');

  final seconds = (totalSeconds % 60).toString().padLeft(2, '0');

  return '$minutes:$seconds';
}

/// Русская десятичная запятая с фиксированной точностью: «0,2».
String formatDecimalRu(double value, {int digits = 1}) {
  return value.toStringAsFixed(digits).replaceAll('.', ',');
}
