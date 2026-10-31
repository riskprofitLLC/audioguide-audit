import 'dart:convert';

import '../../trails/models/trail.dart';
import '../../trails/models/trail_point.dart';


/// Парсер маршрутов из GeoJSON.
///
/// Ожидается FeatureCollection: каждый feature — это
/// LineString или MultiLineString с координатами
/// `[lon, lat]` и properties: id, name, description,
/// distance.

List<Trail> parseTrailsGeoJson(
  String raw,
) {

  final collection =
      jsonDecode(raw) as Map<String, dynamic>;

  final features =
      collection['features'] as List<dynamic>? ?? const [];

  final trails = <Trail>[];

  for (final feature in features.whereType<Map<String, dynamic>>()) {

    final props =
        feature['properties'] as Map<String, dynamic>? ?? {};

    final geometry =
        feature['geometry'] as Map<String, dynamic>?;

    final geomType = geometry?['type'];

    final coords =
        geometry?['coordinates'] as List<dynamic>? ?? const [];

    final lineStrings = <List<dynamic>>[];

    if (geomType == 'MultiLineString') {

      lineStrings.addAll(
        coords.whereType<List<dynamic>>(),
      );

    } else {

      lineStrings.add(coords);

    }

    // id — из properties, фолбэк на name (как в GPX-парсере).
    // Пустой id недопустим: он используется как ключ в SQLite
    // (PRIMARY KEY (island_id, id)), и одинаковые пустые id затирают
    // маршруты друг другом при сидинге.
    final id = props['id'] as String? ??
        props['name'] as String? ??
        '';

    if (id.isEmpty) {
      throw const FormatException('Trail missing required field "id"');
    }

    final lines = <List<TrailPoint>>[];

    var order = 0;

    for (final line in lineStrings) {

      final branch = <TrailPoint>[];

      for (final pair in line.whereType<List<dynamic>>()) {

        // Кривые координаты не должны ронять парсинг без следа:
        // понятная FormatException вместо TypeError/RangeError.
        if (pair.length < 2) {

          throw FormatException(
            'Трек "$id": точка без координат: $pair',
          );
        }

        final lon = pair[0];

        final lat = pair[1];

        if (lat is! num || lon is! num) {

          throw FormatException(
            'Трек "$id": нечисловые координаты: [$lon, $lat]',
          );
        }

        // GeoJSON [lon, lat, elevation?] — высота (A1): без неё
        // профиль высот на web терялся даже при полном GPX.
        final ele = pair.length >= 3 && pair[2] is num
            ? (pair[2] as num).toDouble()
            : null;

        final point = TrailPoint(
          id: '$id:$order',
          latitude: lat.toDouble(),
          longitude: lon.toDouble(),
          order: order++,
          elevation: ele,
        );

        branch.add(point);
      }

      if (branch.isNotEmpty) {
        lines.add(branch);
      }
    }

    if (lines.isEmpty) {
      continue;
    }

    final points = lines.expand((b) => b).toList();

    trails.add(
      Trail(
        id: id,
        name: props['name'] as String? ?? '',
        description: props['description'] as String?,
        distance: (props['distance'] as num?)?.toDouble(),
        points: points,
        lines: lines.length > 1 ? lines : null,
        imagePaths:
            (props['images'] as List<dynamic>?)
                ?.map((e) => e.toString())
                .toList() ??
            const [],
      ),
    );
  }

  return trails;
}
