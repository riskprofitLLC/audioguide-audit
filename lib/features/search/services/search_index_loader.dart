import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../content/models/region_catalog.dart';
import '../models/search_index_entry.dart';

/// Загружает поисковые индексы всех локаций (A10.2, 8-й проход).
///
/// Индексы компактные (6–26 КБ на локацию, весь каталог ~100 КБ) —
/// грузятся один раз за сессию без SQLite и без сидинга контента.
/// Битый/отсутствующий индекс локации пропускается тихо: поиск по
/// остальным работает.
///
/// Баг 11 (замечания Sonnet): записи собираются СТРОГО в порядке
/// [kLocationIds] — раньше `entries.addAll` звался из параллельных
/// задач `Future.wait`, и порядок совпадений при равном весе
/// зависел от того, какая локация прочиталась первой.
@visibleForTesting
Future<List<SearchIndexEntry>> loadSearchIndexWith(
  Future<String> Function(String path) loadString,
) async {
  // Список на локацию: Future.wait сохраняет порядок аргументов,
  // склейка идёт уже после чтения — порядок детерминирован.
  final perLocation = await Future.wait(
    kLocationIds.map((locationId) async {
      try {
        final raw = await loadString(
          '${locationAssetBase(locationId)}/search_index.json',
        );

        final json = jsonDecode(raw) as Map<String, dynamic>;

        final items = json['items'] as List<dynamic>;

        return [
          for (final item in items)
            SearchIndexEntry.fromJson(
              locationId,
              item as Map<String, dynamic>,
            ),
        ];
      } catch (_) {
        // Нет индекса у локации — поиск по ней просто недоступен.
        return const <SearchIndexEntry>[];
      }
    }),
  );

  return [
    for (final entries in perLocation) ...entries,
  ];
}

Future<List<SearchIndexEntry>> loadSearchIndex() {
  return loadSearchIndexWith(rootBundle.loadString);
}
