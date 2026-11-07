// Тесты модели POI: уникальность id и построение пути к аудио.

import 'package:flutter_test/flutter_test.dart';

import 'package:island_guide/features/audio/services/audio_wave.dart';
import 'package:island_guide/features/poi/models/poi.dart';

Poi _poi(String id) {
  return Poi(
    id: id,
    title: 'POI $id',
    latitude: 43.0,
    longitude: 131.9,
  );
}

void main() {
  group('validateUniquePoiIds', () {

    test('уникальные id — без исключения', () {

      expect(() => validateUniquePoiIds([_poi('poi-01'), _poi('poi-02')]),
          returnsNormally);
    });

    test('дубликат id — FormatException', () {

      expect(
        () => validateUniquePoiIds([_poi('poi-01'), _poi('poi-01')]),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('poi-01'),
          ),
        ),
      );
    });
  });

  group('audioAssetPath', () {

    test('собирается из пакета локации и audioPath', () {

      final poi = const Poi(
        id: 'poi-01',
        title: 'Пещера',
        latitude: 43.0,
        longitude: 131.9,
        audioPath: 'no-way/poi-01.mp3',
      );

      expect(
        poi.audioAssetPath('gemiler'),
        'content/fethiye/gemiler/audio/no-way/poi-01.mp3',
      );
    });
  });

  group('audioMs/wave (A8)', () {
    test('fromJson читает audioMs и wave', () {
      final poi = Poi.fromJson({
        'id': 'poi-01',
        'title': 'Маяк',
        'latitude': 36.5,
        'longitude': 29.0,
        'audio': 'no-way/poi-01.mp3',
        'audioMs': 393024,
        'wave': 'AAECAwQFBgcI',
      });

      expect(poi.audioMs, 393024);
      expect(poi.wave, 'AAECAwQFBgcI');
    });

    test('без аудио — audioMs/wave отсутствуют', () {
      final poi = Poi.fromJson({
        'id': 'poi-02',
        'title': 'Мыс',
        'latitude': 36.5,
        'longitude': 29.0,
      });

      expect(poi.audioMs, isNull);
      expect(poi.wave, isNull);
    });
  });

  group('decodeWaveEnvelope (B5)', () {
    test('base64 → нормированные значения', () {
      // base64 байтов [255, 128, 0, 64].
      final wave = decodeWaveEnvelope('/4AAQA==');

      expect(wave, isNotNull);
      expect(wave!.length, 4);
      expect(wave[0], 1.0);
      expect(wave[1], closeTo(128 / 255, 0.001));
      // Полый столбик не ниже визуального минимума.
      expect(wave[2], 0.04);
      expect(wave[3], closeTo(64 / 255, 0.001));
    });

    test('мусор и null — фолбэк', () {
      expect(decodeWaveEnvelope(null), isNull);
      expect(decodeWaveEnvelope(''), isNull);
      expect(decodeWaveEnvelope('%%%'), isNull);
    });
  });
}
