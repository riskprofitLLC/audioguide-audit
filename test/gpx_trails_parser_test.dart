// Тесты парсера GPX-маршрутов.

import 'package:flutter_test/flutter_test.dart';

import 'package:island_guide/features/content/services/gpx_trails_parser.dart';

const _gpxSample = '''
<?xml version="1.0" encoding="UTF-8"?>
<gpx version="1.1" creator="island_guide" xmlns="http://www.topografix.com/GPX/1/1">
  <trk>
    <name>Тропа к мысу</name>
    <desc>Пешеходная тропа.</desc>
    <extensions>
      <id>trail-01</id>
      <distance>3081</distance>
      <images>
        <image>trail-01-1.jpg</image>
        <image>trail-01-2.jpg</image>
      </images>
    </extensions>
    <trkseg>
      <trkpt lat="43.0" lon="131.9"/>
      <trkpt lat="43.001" lon="131.9"/>
      <trkpt lat="43.002" lon="131.901"/>
    </trkseg>
  </trk>
  <trk>
    <name>Маршрут без id</name>
    <trkseg>
      <trkpt lat="43.01" lon="131.91"/>
      <trkpt lat="43.02" lon="131.92"/>
    </trkseg>
  </trk>
</gpx>
''';

void main() {
  group('parseTrailsGpx', () {

    test('парсит название, описание и id из extensions', () {

      final trails = parseTrailsGpx(_gpxSample);

      expect(trails, hasLength(2));

      final first = trails.first;

      expect(first.id, 'trail-01');
      expect(first.name, 'Тропа к мысу');
      expect(first.description, 'Пешеходная тропа.');
    });

    test('читает изображения из extensions.images', () {

      final trails = parseTrailsGpx(_gpxSample);

      expect(
        trails.first.imagePaths,
        ['trail-01-1.jpg', 'trail-01-2.jpg'],
      );

      expect(trails[1].imagePaths, isEmpty);
    });

    test('использует сохранённую дистанцию', () {

      final trails = parseTrailsGpx(_gpxSample);

      expect(trails.first.distance, 3081);
    });

    test('точки берутся из trkseg в порядке следования', () {

      final trails = parseTrailsGpx(_gpxSample);

      final points = trails.first.points;

      expect(points, hasLength(3));
      expect(points.first.latitude, 43.0);
      expect(points.first.longitude, 131.9);
      expect(points.last.latitude, 43.002);
      expect(points[1].order, 1);
    });

    test('без id в extensions используется name', () {

      final trails = parseTrailsGpx(_gpxSample);

      final second = trails[1];

      expect(second.id, 'Маршрут без id');
    });

    test('дистанция вычисляется из точек, если её нет', () {

      final trails = parseTrailsGpx(_gpxSample);

      final second = trails[1];

      // ~1.38 км: 0.01° широты + 0.01° долготы на широте 43°.
      expect(second.distance, closeTo(1377, 15));
    });

    test('пустой документ возвращает пустой список', () {

      final trails = parseTrailsGpx(
        '<?xml version="1.0"?><gpx xmlns="http://www.topografix.com/GPX/1/1"></gpx>',
      );

      expect(trails, isEmpty);
    });

    test('несколько trkseg сохраняются как ветки', () {

      final trails = parseTrailsGpx('''
        <?xml version="1.0"?>
        <gpx version="1.1" xmlns="http://www.topografix.com/GPX/1/1">
          <trk>
            <name>Сеть</name>
            <extensions><id>net</id></extensions>
            <trkseg>
              <trkpt lat="42.0" lon="131.0"/>
              <trkpt lat="42.1" lon="131.1"/>
            </trkseg>
            <trkseg>
              <trkpt lat="42.2" lon="131.2"/>
              <trkpt lat="42.3" lon="131.3"/>
              <trkpt lat="42.4" lon="131.4"/>
            </trkseg>
          </trk>
        </gpx>
      ''');

      final trail = trails.single;

      expect(trail.lines, hasLength(2));
      expect(trail.points, hasLength(5));
      expect(trail.segments, hasLength(2));
      expect(trail.segments.first, hasLength(2));
      expect(trail.segments.last, hasLength(3));
    });

    test('один trkseg — одна ветка', () {

      final trails = parseTrailsGpx(_gpxSample);

      final trail = trails.first;

      expect(trail.lines, isNull);
      expect(trail.segments, hasLength(1));
      expect(trail.segments.single, hasLength(3));
    });

    test('trk без name и id — FormatException (пустой id затирал бы '
        'маршруты в SQLite)', () {

      expect(
        () => parseTrailsGpx('''
          <?xml version="1.0"?>
          <gpx version="1.1" xmlns="http://www.topografix.com/GPX/1/1">
            <trk>
              <trkseg>
                <trkpt lat="43.0" lon="131.9"/>
                <trkpt lat="43.01" lon="131.91"/>
              </trkseg>
            </trk>
          </gpx>
        '''),
        throwsA(isA<FormatException>()),
      );
    });

    test('trk с пустым name и id в extensions — id из extensions', () {

      final trails = parseTrailsGpx('''
        <?xml version="1.0"?>
        <gpx version="1.1" xmlns="http://www.topografix.com/GPX/1/1">
          <trk>
            <name></name>
            <extensions><id>trail-x</id></extensions>
            <trkseg>
              <trkpt lat="43.0" lon="131.9"/>
              <trkpt lat="43.01" lon="131.91"/>
            </trkseg>
          </trk>
        </gpx>
      ''');

      expect(trails.single.id, 'trail-x');
    });

    test('длина считается ПО ВЕТКАМ, без «моста» между trkseg', () {

      // Две ветки по ~111 м каждая, между ними разрыв ~4 км по долготе.
      // Раньше fallback-расчёт шёл по плоскому списку точек и добавлял
      // расстояние «конец первой ветки → начало второй» (~4.2 км).
      final trails = parseTrailsGpx('''
        <?xml version="1.0"?>
        <gpx version="1.1" xmlns="http://www.topografix.com/GPX/1/1">
          <trk>
            <name>Ветки</name>
            <extensions><id>branches</id></extensions>
            <trkseg>
              <trkpt lat="43.000" lon="131.90"/>
              <trkpt lat="43.001" lon="131.90"/>
            </trkseg>
            <trkseg>
              <trkpt lat="43.000" lon="131.95"/>
              <trkpt lat="43.001" lon="131.95"/>
            </trkseg>
          </trk>
        </gpx>
      ''');

      final trail = trails.single;

      expect(trail.lines, hasLength(2));

      // Только сумма длин самих веток (~2×111 м), без межветочного
      // «моста» в ~4.2 км.
      expect(trail.distance, lessThan(500));
      expect(trail.distance, greaterThan(150));
    });
  });
}
