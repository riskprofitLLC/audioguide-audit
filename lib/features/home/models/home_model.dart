/// Модель данных главной страницы (D5/R3 аудита Sonnet): группировка
/// POI по маршрутам вынесена из HomePage в чистый класс без
/// BuildContext — тестируется юнитами.
library;

import '../../../features/poi/models/poi.dart';
import '../../../features/poi/utils/poi_sort.dart';
import '../../../features/trails/models/trail.dart';

/// Группировка главной: отсортированные точки, внемаршрутные точки
/// и маршруты со своими точками.
class HomeModel {
  const HomeModel({
    required this.sortedPois,
    required this.orphanPois,
    required this.trailsWithPois,
  });

  /// Точки локации в порядке отображения.
  final List<Poi> sortedPois;

  /// Внемаршрутные точки (секция «Вне маршрута»).
  final List<Poi> orphanPois;

  /// Маршруты с их точками (без фильтра избранного).
  final List<({Trail trail, List<Poi> allPois})> trailsWithPois;
}

/// Строит модель одним проходом по точкам (A10, 10-й проход).
HomeModel buildHomeModel(List<Poi> pois, List<Trail> trails) {
  final sortedPois = sortPoisForDisplay(pois);

  // Группировка — ОДНИМ проходом по точкам, не фильтром
  // всех POI на каждый маршрут.
  final poisByTrail = <String, List<Poi>>{};

  for (final poi in sortedPois) {
    for (final trailId in poi.trailIds) {
      poisByTrail.putIfAbsent(trailId, () => []).add(poi);
    }
  }

  final trailsWithPois = <({Trail trail, List<Poi> allPois})>[];

  for (final trail in trails) {
    trailsWithPois.add(
      (
        trail: trail,
        allPois: sortPoisForDisplay(
          poisByTrail[trail.id] ?? const <Poi>[],
        ),
      ),
    );
  }

  return HomeModel(
    sortedPois: sortedPois,
    orphanPois: sortedPois.where((p) => p.trailIds.isEmpty).toList(),
    trailsWithPois: trailsWithPois,
  );
}

/// Плоская запись списка главной (A4, 8-й проход).
///
/// Секции «Маршруты» и «Вне маршрута» строятся из чистых данных:
/// ленивый SliverList собирает виджет по индексу записи в
/// itemBuilder, а не держит готовые виджеты.
sealed class HomeEntry {
  const HomeEntry();
}

/// Карточка маршрута.
class TrailEntry extends HomeEntry {
  const TrailEntry({
    required this.trail,
    required this.visibleCount,
    required this.allPois,
    required this.cascadeKeys,
    required this.coverPath,
  });

  final Trail trail;

  /// Число видимых точек маршрута (при звёзд-фильтре — меньше).
  final int visibleCount;

  /// Все точки маршрута (для каскада избранного и «прослушано»).
  final List<Poi> allPois;

  /// Каскад ключей избранного на все точки маршрута.
  final List<String> cascadeKeys;

  final String? coverPath;
}

/// Плитка POI.
class PoiTileEntry extends HomeEntry {
  const PoiTileEntry({
    required this.poi,
    required this.heroTag,
    required this.showDivider,
  });

  final Poi poi;

  /// Тег Hero из чистого предрасчёта (A1) — null у дублей POI.
  final String? heroTag;

  final bool showDivider;
}

/// Вертикальный зазор между карточками маршрутов.
class GapEntry extends HomeEntry {
  const GapEntry(this.height);

  final double height;
}

/// Заглушка «на маршруте нет достопримечательностей».
class EmptyTrailEntry extends HomeEntry {
  const EmptyTrailEntry({required this.message});

  final String message;
}
