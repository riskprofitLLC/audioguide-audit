// Баг 11 (замечания Sonnet): порядок записей поискового индекса
// детерминирован — строго по kLocationIds, независимо от того,
// какая локация прочиталась быстрее.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:island_guide/features/content/models/region_catalog.dart';
import 'package:island_guide/features/search/services/search_index_loader.dart';

String _indexJson(String id) => jsonEncode({
      'items': [
        {
          'kind': 'poi',
          'id': id,
          'title': 'Точка $id',
          'subtitle': '',
        },
      ],
    });

/// Локация из пути `content/<регион>/<локация>/search_index.json`.
String _locationOf(String path) => path.split('/')[2];

void main() {
  test('записи идут в порядке kLocationIds, а не завершения чтения',
      () async {
    // Задержка ОБРАТНАЯ порядку: последняя локация каталога
    // читается первой. При старой реализации (entries.addAll из
    // параллельных задач Future.wait) порядок следовал бы за
    // временем завершения, а не за списком.
    final entries = await loadSearchIndexWith((path) async {
      final locationId = _locationOf(path);

      await Future<void>.delayed(
        Duration(
          milliseconds:
              10 * (kLocationIds.length - kLocationIds.indexOf(locationId)),
        ),
      );

      return _indexJson(locationId);
    });

    expect(entries, hasLength(kLocationIds.length));

    // Порядок ровно каталожный.
    expect(
      entries.map((e) => e.locationId).toList(),
      kLocationIds,
    );

    for (var i = 0; i < kLocationIds.length; i++) {
      expect(entries[i].id, kLocationIds[i]);
    }
  });

  test('битый индекс локации пропускается, порядок остальных сохранён',
      () async {
    final entries = await loadSearchIndexWith((path) async {
      final locationId = _locationOf(path);

      if (locationId == kLocationIds.first) {
        throw const FormatException('битый json');
      }

      return _indexJson(locationId);
    });

    expect(
      entries.map((e) => e.locationId).toList(),
      kLocationIds.skip(1).toList(),
    );
  });
}
