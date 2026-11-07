// Тесты подсчёта длительности MP3 по байтам файла.
//
// Реальные файлы озвучки читаются с диска (dart:io) и
// сравниваются с эталонными длительностями (ffprobe).

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:island_guide/features/audio/services/mp3_duration.dart';

void main() {
  // Инвариант (Б14, замечание Sonnet): длительность, вычисленная
  // из байтов MP3, должна совпадать с audioMs из poi.json (его
  // пишет ffprobe в generate_audio.py) с допуском на разницу
  // метрик битрейта. Жёсткие числа ломались при перегенерации
  // озвучки.
  final poiEntries = (jsonDecode(
    File('content/fethiye/gemiler/poi.json').readAsStringSync(),
  ) as List<dynamic>)
      .cast<Map<String, dynamic>>()
      .where((poi) => poi['audioMs'] != null)
      .map((poi) => (
            id: poi['id'] as String,
            audioPath: poi['audio'] as String,
            audioMs: poi['audioMs'] as int,
          ))
      .toList();

  group('mp3DurationFromBytes', () {
    for (final entry in poiEntries) {
      test('${entry.id}.mp3 ≈ audioMs ${entry.audioMs} мс', () {
        final file = File(
          'content/fethiye/gemiler/audio/${entry.audioPath}',
        );
        final bytes = Uint8List.fromList(file.readAsBytesSync());

        final duration = mp3DurationFromBytes(bytes);

        expect(duration, isNotNull);

        // Допуск: 2% + 500 мс (заполнение последнего фрейма,
        // VBR-заголовок vs ffprobe).
        final tolerance = (entry.audioMs * 0.02).round() + 500;

        expect(
          (duration!.inMilliseconds - entry.audioMs).abs(),
          lessThanOrEqualTo(tolerance),
          reason: 'длительность из байтов должна совпадать с audioMs '
              'из poi.json (эталон ffprobe) в пределах допуска',
        );
      });
    }

    test('пустые данные → null', () {
      expect(mp3DurationFromBytes(Uint8List(0)), isNull);
    });

    test('мусор без синка → null', () {
      final garbage = Uint8List.fromList(List.filled(64, 0x55));
      expect(mp3DurationFromBytes(garbage), isNull);
    });

    test('обрезанный последний фрейм не считается (P2)', () {
      // MPEG1 Layer III, 128 kbps, 44100 Гц → фрейм 417 байт,
      // 1152 сэмпла.
      final header = <int>[0xFF, 0xFB, 0x90, 0x00];

      final frame = Uint8List(417)..setRange(0, 4, header);

      final bytes = Uint8List(417 * 2 + 100)
        ..setRange(0, 417, frame)
        ..setRange(417, 834, frame)
        ..setRange(834, 838, header);

      final duration = mp3DurationFromBytes(bytes)!;

      // 2 полных фрейма × 1152 / 44100 ≈ 52 мс (без фикса было бы 78).
      expect(duration.inMilliseconds, 52);
    });
  });

  group('mp3DurationOfAsset (кеш по пути)', () {
    setUpAll(() {
      // rootBundle в plain-тесте читает ассеты пакета.
      TestWidgetsFlutterBinding.ensureInitialized();
    });

    setUp(clearMp3DurationCache);

    test('повторный вызов того же ассета не перечитывает файл', () async {
      final asset =
          'content/fethiye/gemiler/audio/${poiEntries.first.audioPath}';

      expect(mp3DurationCacheSize, 0);

      final first = await mp3DurationOfAsset(asset);
      final second = await mp3DurationOfAsset(asset);

      expect(first, isNotNull);
      expect(second, first);
      expect(mp3DurationCacheSize, 1,
          reason: 'длительность должна закешироваться один раз');
    });

    test('несуществующий ассет кешируется как null', () async {
      expect(mp3DurationCacheSize, 0);

      final first = await mp3DurationOfAsset('no-such-file.mp3');
      final second = await mp3DurationOfAsset('no-such-file.mp3');

      expect(first, isNull);
      expect(second, isNull);
      expect(mp3DurationCacheSize, 1);
    });
  });
}