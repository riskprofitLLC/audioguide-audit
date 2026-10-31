import '../../gps/models/user_position.dart';
import '../../gps/services/location_service.dart';
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

/// Ближайшая к пользователю точка (A15, 17-й проход).
class NearestPoiMatch {

  const NearestPoiMatch({
    required this.poi,
    required this.locationId,
    required this.distance,
    required this.bearing,
  });


  final Poi poi;


  /// Локация точки (id повторяются между локациями).
  final String locationId;


  /// Дистанция (метры).
  final double distance;


  /// Азимут на точку (0 — север).
  final double bearing;
}

/// Ищет ближайшую к пользователю ВИДИМУЮ точку (A15, 17-й проход).
///
/// При активном фильтре категорий кандидатами считаются только
/// точки, которые фильтр НЕ прячет: чип «ближайшая точка» не
/// должен предлагать объект, которого на карте нет. `null` —
/// точек нет.
NearestPoiMatch? nearestVisiblePoi({
  required UserPosition position,
  required List<Poi> pois,
  required List<String> locations,
  String? category,
}) {
  Poi? nearest;

  String? nearestLocation;

  double? nearestDistance;

  double? nearestBearing;

  for (var i = 0; i < pois.length; i++) {

    final poi = pois[i];

    // Фильтр прячет точку — она не кандидат (A15).
    if (category != null && poi.category != category) {
      continue;
    }

    final distance = LocationService.distanceMeters(
      position.latitude,
      position.longitude,
      poi.latitude,
      poi.longitude,
    );

    if (nearestDistance == null || distance < nearestDistance) {

      nearest = poi;

      nearestLocation = locations.isEmpty
          ? ''
          : locations[i];

      nearestDistance = distance;

      nearestBearing = LocationService.bearingDegrees(
        position.latitude,
        position.longitude,
        poi.latitude,
        poi.longitude,
      );
    }
  }

  if (nearest == null || nearestLocation == null) {
    return null;
  }

  return NearestPoiMatch(
    poi: nearest,
    locationId: nearestLocation,
    distance: nearestDistance!,
    bearing: nearestBearing!,
  );
}
