import '../../poi/models/poi.dart';

/// Фильтр POI карты по категории (1c, 12-й проход): `null` — все
/// точки, иначе — только точки выбранной категории.
///
/// Работает с ПАРАЛЛЕЛЬНЫМИ списками POI/локаций (формат данных
/// карты): фильтр обязан сохранить соответствие элементов.
({List<Poi> pois, List<String> locations}) filterPoisByCategory(
  List<Poi> pois,
  List<String> locations,
  String? category,
) {
  if (category == null) {
    return (pois: pois, locations: locations);
  }

  final filteredPois = <Poi>[];

  final filteredLocations = <String>[];

  for (var i = 0; i < pois.length; i++) {
    if (pois[i].category == category) {
      filteredPois.add(pois[i]);

      filteredLocations.add(locations[i]);
    }
  }

  return (pois: filteredPois, locations: filteredLocations);
}
