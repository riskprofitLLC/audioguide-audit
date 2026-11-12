// Инвариант озвучки региона Киликия: ни одной точки без аудио.
// Озвучка посегментная (msedge, без меток и словаря) — папка
// audio/<way|no-way>/poi-XX/ с NNN.mp3 + manifest.json. Единого mp3
// точки в контенте НЕТ: плеер играет предложения подряд, единый путь
// остаётся только логическим идентификатором трека (35-й проход).

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:island_guide/features/poi/services/poi_json_parser.dart';

const List<String> _locations = <String>[
  'content/kilikia/antalya-gazipasha',
  'content/kilikia/gazipasha-tashuju',
  'content/kilikia/tashuju-mersin',
];

void main() {
  for (final base in _locations) {
    final raw = File('$base/poi.json').readAsStringSync();

    test('$base: все точки озвучены, файлы предложений на месте', () async {
      final pois = await parsePoisJson(raw);

      expect(pois, isNotEmpty);
      for (final poi in pois) {
        final reason = '${base.split('/').last}/${poi.id}';
        expect(poi.audioPath, isNotNull, reason: reason);
        expect(poi.audioSentences, greaterThan(0), reason: reason);
        expect(poi.audioMs, greaterThan(0), reason: reason);
        expect(poi.wave, isNotEmpty, reason: reason);

        // Логический идентификатор трека — поле audio в poi.json; файла
        // с таким именем в контенте нет и не должно быть.
        expect(File('$base/audio/${poi.audioPath}').existsSync(), isFalse,
            reason: '$reason: единый mp3 не хранится');

        // Каждое предложение — свой файл, число совпадает с poi.json.
        final paths = poi.sentenceAssetPaths(base.split('/').last);
        expect(paths, hasLength(poi.audioSentences!), reason: reason);
        for (final path in paths) {
          expect(File('$base/audio/${path.split('/audio/').last}').existsSync(),
              isTrue,
              reason: '$reason: $path');
        }

        // Манифест посегментной озвучки перечисляет те же файлы.
        final manifest = File('$base/audio/no-way/${poi.id}/manifest.json');
        expect(manifest.existsSync(), isTrue, reason: reason);
        final data = jsonDecode(manifest.readAsStringSync())
            as Map<String, dynamic>;
        expect((data['sentences'] as List).length, poi.audioSentences,
            reason: reason);
      }
    });
  }
}
