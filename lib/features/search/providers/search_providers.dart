import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/search_index_entry.dart';
import '../services/search_index_loader.dart';

/// Поисковый индекс всего каталога (A10.2, 8-й проход).
///
/// Компактные готовые индексы локаций вместо подписки на
/// poisFamily/trailsFamily всех локаций: на native прежняя схема
/// при первом запросе запускала холодный сидинг всех 9 пакетов.
/// Грузится один раз за сессию; поиск больше не будит сидинг.
final searchIndexProvider = FutureProvider<List<SearchIndexEntry>>((
  ref,
) async {
  return loadSearchIndex();
});
