import 'package:flutter_test/flutter_test.dart';

import 'package:island_guide/features/content/services/geojson_trails_parser.dart';

void main() {
  const raw = '''
  {
    "type": "FeatureCollection",
    "features": [
      {
        "type": "Feature",
        "properties": {
          "id": "trail-01",
          "name": "Тропа",
          "description": "Описание",
          "distance": 1500,
          "images": ["trail-01-1.jpg", "trail-01-2.jpg"]
        },
        "geometry": {
          "type": "LineString",
          "coordinates": [
            [131.75, 42.93],
            [131.76, 42.94],
            [131.77, 42.95]
          ]
        }
      }
    ]
  }
  ''';

  test('парсит LineString и меняет местами координаты', () {
    final trails = parseTrailsGeoJson(raw);

    expect(trails, hasLength(1));

    final trail = trails.first;

    expect(trail.id, 'trail-01');
    expect(trail.name, 'Тропа');
    expect(trail.distance, 1500);
    expect(trail.points, hasLength(3));

    expect(trail.points.first.longitude, closeTo(131.75, 0.0001));
    expect(trail.points.first.latitude, closeTo(42.93, 0.0001));

    expect(trail.points[1].order, 1);
  });

  test('читает images из properties', () {
    final trails = parseTrailsGeoJson(raw);

    expect(
      trails.first.imagePaths,
      ['trail-01-1.jpg', 'trail-01-2.jpg'],
    );
  });

  test('без images список пуст', () {
    final trails = parseTrailsGeoJson('''
      {
        "type": "FeatureCollection",
        "features": [
          {
            "type": "Feature",
            "properties": {"id": "x", "name": "X"},
            "geometry": {"type": "LineString", "coordinates": [[131.0, 42.0]]}
          }
        ]
      }
    ''');

    expect(trails.first.imagePaths, isEmpty);
  });

  test('пустой список фич возвращает пустой список', () {
    final trails = parseTrailsGeoJson(
      '{"type": "FeatureCollection", "features": []}',
    );

    expect(trails, isEmpty);
  });

  test('точки без координат пропускаются', () {
    final trails = parseTrailsGeoJson('''
      {
        "type": "FeatureCollection",
        "features": [
          {
            "type": "Feature",
            "properties": {"id": "x", "name": "X"},
            "geometry": {"type": "LineString", "coordinates": []}
          }
        ]
      }
    ''');

    expect(trails, isEmpty);
  });

  test('MultiLineString сохраняет ветки', () {
    final trails = parseTrailsGeoJson('''
      {
        "type": "FeatureCollection",
        "features": [
          {
            "type": "Feature",
            "properties": {"id": "trail-net", "name": "Сеть"},
            "geometry": {
              "type": "MultiLineString",
              "coordinates": [
                [[131.0, 42.0], [131.1, 42.1]],
                [[131.2, 42.2], [131.3, 42.3], [131.4, 42.4]]
              ]
            }
          }
        ]
      }
    ''');

    final trail = trails.single;

    expect(trail.lines, hasLength(2));
    expect(trail.points, hasLength(5));
    expect(trail.segments, hasLength(2));
    expect(trail.segments.first, hasLength(2));
    expect(trail.segments.last, hasLength(3));
  });

  test('LineString — одна ветка', () {
    final trails = parseTrailsGeoJson(raw);

    final trail = trails.single;

    expect(trail.lines, isNull);
    expect(trail.segments, hasLength(1));
    expect(trail.segments.single, hasLength(3));
  });

  test('без id в properties используется name', () {
    final trails = parseTrailsGeoJson('''
      {
        "type": "FeatureCollection",
        "features": [
          {
            "type": "Feature",
            "properties": {"name": "Тропа из имени"},
            "geometry": {
              "type": "LineString",
              "coordinates": [[131.0, 42.0], [131.1, 42.1]]
            }
          }
        ]
      }
    ''');

    expect(trails.single.id, 'Тропа из имени');
  });

  test('без id и name — FormatException (пустой id затирал бы маршруты '
      'в SQLite)', () {
    expect(
      () => parseTrailsGeoJson('''
        {
          "type": "FeatureCollection",
          "features": [
            {
              "type": "Feature",
              "properties": {},
              "geometry": {
                "type": "LineString",
                "coordinates": [[131.0, 42.0], [131.1, 42.1]]
              }
            }
          ]
        }
      '''),
      throwsA(isA<FormatException>()),
    );
  });

  test('точка без пары координат — понятная FormatException', () {
    // Раньше pair[1] ронял парсинг TypeError'ом/RangeError'ом без
    // указания, какой трек битый.
    expect(
      () => parseTrailsGeoJson('''
        {
          "type": "FeatureCollection",
          "features": [
            {
              "type": "Feature",
              "properties": {"id": "trail-x", "name": "X"},
              "geometry": {
                "type": "LineString",
                "coordinates": [[131.0, 42.0], [131.1]]
              }
            }
          ]
        }
      '''),
      throwsA(
        isA<FormatException>().having(
          (e) => e.message,
          'message',
          contains('trail-x'),
        ),
      ),
    );
  });

  test('нечисловые координаты — FormatException с id трека', () {
    expect(
      () => parseTrailsGeoJson('''
        {
          "type": "FeatureCollection",
          "features": [
            {
              "type": "Feature",
              "properties": {"id": "trail-bad", "name": "X"},
              "geometry": {
                "type": "LineString",
                "coordinates": [["131.0", 42.0]]
              }
            }
          ]
        }
      '''),
      throwsA(
        isA<FormatException>().having(
          (e) => e.message,
          'message',
          contains('trail-bad'),
        ),
      ),
    );
  });
}
