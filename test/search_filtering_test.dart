// groupSearchEntries / сортировка по дистанции (D5): чистая логика
// поиска вынесена из tree_navigation_sheet — юнит-тесты без виджетов.

import 'package:flutter_test/flutter_test.dart';

import 'package:island_guide/features/navigation/models/search_filtering.dart';
import 'package:island_guide/features/search/models/search_index_entry.dart';

SearchIndexEntry _poi(
  String id,
  String title, {
  double? lat,
  double? lng,
  String? desc,
}) =>
    SearchIndexEntry(
      kind: SearchEntryKind.poi,
      locationId: 'gemiler',
      id: id,
      title: title,
      subtitle: 'Залив Фетхие · Остров Гемилер',
      lat: lat,
      lng: lng,
      desc: desc,
    );

void main() {
  test('нормализация: регистр, ё→е, лишние пробелы', () {
    expect(normalizeSearchQuery('  Гё QUER  '), 'ге quer');

    expect(matchesFolding('гемилер', 'Остров Гемилер'), isTrue);

    expect(matchesFolding('остров', 'Остров'), isTrue);
  });

  test('группировка: по названию выше, по описанию ниже', () {
    final index = [
      _poi('poi-01', 'Церковь', lat: 36.60, lng: 29.10),
      _poi('poi-02', 'Другое', lat: 36.70, lng: 29.10, desc: 'церковь внутри'),
      const SearchIndexEntry(
        kind: SearchEntryKind.trail,
        locationId: 'gemiler',
        id: 'trail-01',
        title: 'Маршрут',
        subtitle: '',
      ),
    ];

    final groups = groupSearchEntries(index, normalizeSearchQuery('церковь'));

    expect(groups.poiByTitle.map((e) => e.id), ['poi-01']);

    expect(groups.poiByMetadata.map((e) => e.id), ['poi-02']);

    expect(groups.trails, isEmpty);
  });

  test('сортировка по дистанции: ближайшие сверху, без координат — в конец', () {
    final entries = [
      _poi('far', 'А', lat: 36.70, lng: 29.10),
      _poi('no-coords', 'Б'),
      _poi('near', 'В', lat: 36.60, lng: 29.10),
    ];

    sortEntriesByDistance(entries, userLat: 36.60, userLng: 29.10);

    expect(entries.map((e) => e.id), ['near', 'far', 'no-coords']);

    // Без позиции порядок не трогаем.
    final shuffled = [...entries.reversed];

    sortEntriesByDistance(shuffled);

    expect(shuffled.map((e) => e.id), ['no-coords', 'far', 'near']);
  });
}
