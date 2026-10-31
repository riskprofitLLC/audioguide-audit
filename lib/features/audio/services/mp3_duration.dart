import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';


/// Кеш длительностей по пути ассета.
///
/// Парсинг MP3 по байтам — чтение всего файла и проход по фреймам;
/// он выполняется при создании каждого виджета плеера, а трек
/// открывается повторно (возврат на POI, автогид). Кешируется и
/// `null` (битый файл), чтобы не перечитывать мусор каждый раз.
final Map<String, Duration?> _durationCache = {};


/// Сбрасывает кеш длительностей (используется тестами).
@visibleForTesting
void clearMp3DurationCache() {
  _durationCache.clear();
}


/// Число закешированных длительностей (используется тестами).
@visibleForTesting
int get mp3DurationCacheSize => _durationCache.length;


/// Длительность MP3-ассета (например,
/// `content/gemiler/audio/poi-01.mp3`).
///
/// Результат кешируется по пути: повторное открытие того же трека
/// не перечитывает и не парсит файл заново.
Future<Duration?> mp3DurationOfAsset(
  String assetPath,
) async {

  if (_durationCache.containsKey(assetPath)) {

    return _durationCache[assetPath];
  }

  try {

    final data = await rootBundle.load(assetPath);

    final bytes = data.buffer.asUint8List(
      data.offsetInBytes,
      data.lengthInBytes,
    );

    final duration = mp3DurationFromBytes(bytes);

    _durationCache[assetPath] = duration;

    return duration;

  } catch (_) {

    _durationCache[assetPath] = null;

    return null;
  }
}


/// Считает длительность MP3 по байтам файла, не декодируя его.
///
/// Плеер just_audio на web не обновляет длительность при смене
/// источника на одном экземпляре — остаётся длительность первого
/// загруженного файла. Поэтому длительность считается напрямую из
/// байтов: подсчёт сэмплов всех фреймов MPEG Layer III (точный и
/// для CBR, и для VBR).
Duration? mp3DurationFromBytes(Uint8List data) {

  final length = data.length;

  var position = 0;

  // Пропускаем ID3v2-тег в начале, если есть.
  if (length >= 10 &&
      data[0] == 0x49 &&
      data[1] == 0x44 &&
      data[2] == 0x33) {

    final size = (data[6] & 0x7f) << 21 |
        (data[7] & 0x7f) << 14 |
        (data[8] & 0x7f) << 7 |
        (data[9] & 0x7f);

    position = 10 + size;
  }

  var totalSamples = 0;

  var sampleRate = 0;

  while (position + 4 <= length) {

    final frame = _parseMp3Frame(data, position);

    if (frame == null) {

      // Мусорные байты (например, LAME-тег в первом фрейме):
      // ищем следующий синк.
      position += 1;

      continue;
    }

    totalSamples += frame.samplesPerFrame;

    sampleRate = frame.sampleRate;

    position += frame.frameSize;
  }

  if (sampleRate <= 0) {

    return null;
  }

  return Duration(
    milliseconds: (totalSamples / sampleRate * 1000).round(),
  );
}


/// Битрейты MPEG Layer III (kbps) по версии MPEG.
const Map<int, List<int>> _bitrateTable = {
  3: [0, 32, 40, 48, 56, 64, 80, 96, 112, 128, 160, 192, 224, 256, 320, 0],
  2: [0, 8, 16, 24, 32, 40, 48, 56, 64, 80, 96, 112, 128, 144, 160, 0],
  0: [0, 8, 16, 24, 32, 40, 48, 56, 64, 80, 96, 112, 128, 144, 160, 0],
};


/// Частоты дискретизации (Гц) по версии MPEG и индексу.
const Map<int, List<int>> _sampleRateTable = {
  3: [44100, 48000, 32000],
  2: [22050, 24000, 16000],
  0: [11025, 12000, 8000],
};


class _Mp3Frame {

  const _Mp3Frame(
    this.frameSize,
    this.samplesPerFrame,
    this.sampleRate,
  );


  final int frameSize;

  final int samplesPerFrame;

  final int sampleRate;
}


_Mp3Frame? _parseMp3Frame(
  Uint8List data,
  int position,
) {

  final b0 = data[position];

  final b1 = data[position + 1];

  final b2 = data[position + 2];

  // Синк — 11 бит (0xFFE...).
  if (b0 != 0xff || (b1 & 0xe0) != 0xe0) {

    return null;
  }

  // Версия: 11 = MPEG1, 10 = MPEG2, 00 = MPEG2.5,
  // 01 = зарезервирована.
  final version = (b1 >> 3) & 0x03;

  if (version == 1) {

    return null;
  }

  // Слой: 01 = Layer III (остальные не используются).
  final layer = (b1 >> 1) & 0x03;

  if (layer != 1) {

    return null;
  }

  final bitrateIndex = (b2 >> 4) & 0x0f;

  final sampleRateIndex = (b2 >> 2) & 0x03;

  final padding = (b2 >> 1) & 0x01;

  if (sampleRateIndex == 3 || bitrateIndex == 15 || bitrateIndex == 0) {

    return null;
  }

  final bitrate = _bitrateTable[version]![bitrateIndex] * 1000;

  final sampleRate = _sampleRateTable[version]![sampleRateIndex];

  // Размер фрейма Layer III: MPEG1 — 144 × bitrate / rate,
  // MPEG2/2.5 — 72 × bitrate / rate (+ padding). Сэмплов на фрейм:
  // MPEG1 — 1152, MPEG2/2.5 — 576.
  final frameSize =
      (version == 3
          ? 144 * bitrate ~/ sampleRate
          : 72 * bitrate ~/ sampleRate) +
      padding;

  final samplesPerFrame = version == 3 ? 1152 : 576;

  return _Mp3Frame(frameSize, samplesPerFrame, sampleRate);
}