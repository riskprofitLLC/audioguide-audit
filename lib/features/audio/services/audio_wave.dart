import 'dart:convert';
import 'dart:typed_data';

/// Разбор огибающей громкости аудио из поля poi.json `wave`
/// (A8/B5, 8-й проход).
///
/// Формат: base64-строка из 80 байт, каждый — RMS окна 0–255,
/// нормированный на пик дорожки. Пишет `tool/generate_audio.py`
/// (`--durations-only` тоже). Возвращает нормированные значения
/// 0..1 для художника волны плеера; `null` — строка отсутствует
/// или битая, плеер остаётся на декоративном фолбэке.
List<double>? decodeWaveEnvelope(String? encoded) {
  if (encoded == null || encoded.isEmpty) {
    return null;
  }

  Uint8List bytes;

  try {
    bytes = base64Decode(encoded);
  } on FormatException {
    return null;
  }

  // Разумный потолок: волна — компактная огибающая, не сырые
  // сэмплы. Что-то за килобайт — мусор в поле.
  if (bytes.isEmpty || bytes.length > 1024) {
    return null;
  }

  return [
    for (final value in bytes)
      // Полые (нулевые) столбики рисуются высотой 2 px.
      (value / 255).clamp(0.04, 1.0),
  ];
}
