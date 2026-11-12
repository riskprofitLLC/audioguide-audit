// Контент-инварианты локации «Ташуджу — Мерсин» (33-й проход):
// POI идут с запада на восток, АУДИО озвучено посегментно (msedge),
// фото залиты (по 1 кадру на точку), координаты внутри islandBounds
// манифеста, категории известны приложению.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:island_guide/features/poi/services/poi_json_parser.dart';
import 'package:island_guide/features/poi/utils/poi_category.dart';

const String _base = 'content/kilikia/tashuju-mersin';

void main() {
  final raw = File('$_base/poi.json').readAsStringSync();
  final manifest =
      jsonDecode(File('$_base/manifest.json').readAsStringSync())
          as Map<String, dynamic>;

  test('манифест локации совпадает с каталогом', () {
    expect(manifest['id'], 'tashuju-mersin');
    expect(manifest['name'], 'Ташуджу — Мерсин');
    expect(manifest['map'], '');
  });

  test('poi.json разбирается в 20 точек с последовательными id', () async {
    final pois = await parsePoisJson(raw);

    expect(pois, hasLength(20));
    expect(
      [for (final p in pois) p.id],
      [for (var i = 1; i <= 20; i++) 'poi-${i.toString().padLeft(2, '0')}'],
    );
  });

  test('POI идут с запада на восток', () async {
    final pois = await parsePoisJson(raw);

    for (var i = 1; i < pois.length; i++) {
      expect(pois[i].longitude, greaterThan(pois[i - 1].longitude - 0.01),
          reason: '${pois[i - 1].id} → ${pois[i].id}');
    }
  });

  test('аудио озвучено, фото на месте, категории и тексты на месте',
      () async {
    final pois = await parsePoisJson(raw);
    final bounds = manifest['islandBounds'] as Map<String, dynamic>;

    for (final poi in pois) {
      // Озвучка посегментная: логический единый файл + число предложений.
      expect(poi.audioPath, isNotNull, reason: poi.id);
      expect(poi.audioSentences, greaterThan(0), reason: poi.id);
      expect(poi.audioMs, greaterThan(0), reason: poi.id);
      // Фото залиты: у каждой точки есть хотя бы один кадр.
      expect(poi.imagePaths, isNotEmpty, reason: poi.id);
      expect(poi.trailIds, isEmpty, reason: poi.id);
      expect(poi.title, isNotEmpty, reason: poi.id);
      expect(poi.description!.length, greaterThan(500), reason: poi.id);
      expect(kPoiCategories.containsKey(poi.category), isTrue,
          reason: '${poi.id}: неизвестная категория ${poi.category}');
      expect(poi.latitude, lessThanOrEqualTo(bounds['north'] as double));
      expect(poi.latitude, greaterThanOrEqualTo(bounds['south'] as double));
      expect(poi.longitude, lessThanOrEqualTo(bounds['east'] as double));
      expect(poi.longitude, greaterThanOrEqualTo(bounds['west'] as double));
    }
  });

  test('поисковый индекс Location знает локацию', () {
    final index = jsonDecode(File('$_base/search_index.json').readAsStringSync())
        as Map<String, dynamic>;
    final items = (index['items'] as List<dynamic>)
        .cast<Map<String, dynamic>>();

    expect(items.first['kind'], 'location');
    expect(items.first['id'], 'tashuju-mersin');
    expect(items.first['title'], 'Ташуджу — Мерсин');
    expect(items, hasLength(21));
  });
}
