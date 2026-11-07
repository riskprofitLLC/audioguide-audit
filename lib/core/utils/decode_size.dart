import 'package:flutter/widgets.dart';


/// Ширина декодирования изображения для миниатюры/карточки.
///
/// Без `cacheWidth` Flutter декодирует ассет в полном размере
/// (например, фото ~1200 px для 40-пиксельной миниатюры) — это
/// лишние мегабайты памяти и времени декодирования на каждый билд
/// списка. Здесь логический размер умножается на DPR устройства и
/// [oversample] — небольшой запас качества (масштабирование
/// виджета, анимации, будущие retina-темы).
///
/// Возвращает `null`, если контекст без MediaQuery (в тестах) —
/// Flutter сам выберет разумный размер.
int? decodeWidthPx(
  BuildContext context,
  double logicalWidth, {
  double oversample = 2,
}) {

  final dpr = MediaQuery.maybeDevicePixelRatioOf(context);

  if (dpr == null) {
    return null;
  }

  return (logicalWidth * dpr * oversample).round();
}
