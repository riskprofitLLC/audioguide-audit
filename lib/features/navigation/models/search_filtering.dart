/// Чистая логика поиска по индексу (D5 аудита Sonnet): нормализация
/// запроса, регистронезависимое совпадение и группировка результатов
/// вынесены из tree_navigation_sheet в функции без BuildContext.
library;

import '../../gps/services/location_service.dart';
import '../../poi/utils/poi_category.dart';
import '../../search/models/search_index_entry.dart';

/// Свёртка для поиска: регистр, ё→е. Длина строки сохраняется —
/// по свёрнутой копии можно подсветить совпадение в оригинале.
String foldSearchText(String value) =>
    value.toLowerCase().replaceAll('ё', 'е');

/// Нормализованный запрос: свёрнут + повторные пробелы схлопнуты.
String normalizeSearchQuery(String query) =>
    foldSearchText(query).replaceAll(RegExp(r'\s+'), ' ').trim();

/// Подстрока поиска: регистронезависимое вхождение (кириллица + латиница).
bool matchesFolding(String normalizedQuery, String value) =>
    foldSearchText(value).contains(normalizedQuery);

/// Сгруппированные результаты поиска: Локации / Маршруты / Места
/// (по названию, затем по категории/описанию — пониженный приоритет).
class SearchGroups {
  const SearchGroups({
    required this.locations,
    required this.trails,
    required this.trailsByDescription,
    required this.poiByTitle,
    required this.poiByMetadata,
  });

  final List<SearchIndexEntry> locations;

  final List<SearchIndexEntry> trails;

  /// Маршруты, совпавшие по описанию (ниже совпадений по названию).
  final List<SearchIndexEntry> trailsByDescription;

  final List<SearchIndexEntry> poiByTitle;

  /// Места, совпавшие по категории или описанию (в конце списка).
  final List<SearchIndexEntry> poiByMetadata;
}

/// Группирует записи индекса по нормализованному запросу.
SearchGroups groupSearchEntries(
  List<SearchIndexEntry> index,
  String normalized,
) {
  final locations = <SearchIndexEntry>[];

  final trails = <SearchIndexEntry>[];

  final trailsByDescription = <SearchIndexEntry>[];

  final poiByTitle = <SearchIndexEntry>[];

  final poiByMetadata = <SearchIndexEntry>[];

  for (final entry in index) {
    switch (entry.kind) {
      case SearchEntryKind.location:
        if (matchesFolding(normalized, entry.title) ||
            matchesFolding(normalized, entry.id)) {
          locations.add(entry);
        }

      case SearchEntryKind.trail:
        if (matchesFolding(normalized, entry.title)) {
          trails.add(entry);
        } else if (entry.desc != null &&
            matchesFolding(normalized, entry.desc!)) {
          trailsByDescription.add(entry);
        }

      case SearchEntryKind.poi:
        // Записи собираются списками, ряды строятся после сортировки.
        final label = entry.displayTitle;

        if (matchesFolding(normalized, label)) {
          poiByTitle.add(entry);
        } else if ((entry.category != null &&
                matchesFolding(normalized, poiCategoryLabel(entry.category))) ||
            (entry.desc != null && matchesFolding(normalized, entry.desc!))) {
          poiByMetadata.add(entry);
        }
    }
  }

  return SearchGroups(
    locations: locations,
    trails: trails,
    trailsByDescription: trailsByDescription,
    poiByTitle: poiByTitle,
    poiByMetadata: poiByMetadata,
  );
}

/// «Рядом» (1a, 12-й проход): с известной позицией подгруппа
/// сортируется по дистанции; без координат — в конец, порядок
/// стабилен. Без позиции порядок прежний (по индексу).
void sortEntriesByDistance(
  List<SearchIndexEntry> entries, {
  double? userLat,
  double? userLng,
}) {
  if (userLat == null || userLng == null) {
    return;
  }

  double? distanceOf(SearchIndexEntry e) {
    if (e.lat == null || e.lng == null) {
      return null;
    }

    return LocationService.distanceMeters(
      userLat,
      userLng,
      e.lat!,
      e.lng!,
    );
  }

  entries.sort((a, b) {
    final da = distanceOf(a);
    final db = distanceOf(b);

    if (da == null) return db == null ? 0 : 1;
    if (db == null) return -1;

    return da.compareTo(db);
  });
}
