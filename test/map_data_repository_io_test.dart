// Round-trip тесты MapDataRepository на native-реализации (SQLite):
// результат чтения из БД должен совпадать с прямым парсингом ассетов.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:island_guide/core/services/database_service.dart';
import 'package:island_guide/features/content/services/geojson_trails_parser.dart';
import 'package:island_guide/features/map/data/map_data_repository.dart';
import 'package:island_guide/features/poi/models/poi.dart';
import 'package:island_guide/features/trails/models/trail.dart';
import 'package:island_guide/features/trails/models/trail_point.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('island_guide_test');
    await DatabaseService.instance.initialize(databaseDirectory: tmp.path);
  });

  tearDown(() {
    DatabaseService.instance.close();
    tmp.deleteSync(recursive: true);
  });

  test('loadPois round-trip: чтение из БД совпадает с прямым парсингом poi.json',
      () async {
    final pois = await const MapDataRepository(islandId: 'gemiler').loadPois();

    final raw = await rootBundle.loadString('content/fethiye/gemiler/poi.json');

    final expected = (jsonDecode(raw) as List<dynamic>)
        .whereType<Map<String, dynamic>>()
        .map(Poi.fromJson)
        .toList();

    expect(_poiKeys(pois), _poiKeys(expected));
  });

  test('loadTrails round-trip: чтение из БД совпадает с прямым парсингом trails.geojson',
      () async {
    // Сидер приоритетно кладёт в БД GeoJSON (единый порядок с web),
    // поэтому ожидание строится от trails.geojson.
    final trails =
        await const MapDataRepository(islandId: 'gemiler').loadTrails();

    final raw = await rootBundle.loadString('content/fethiye/gemiler/trails.geojson');

    final expected = parseTrailsGeoJson(raw);

    expect(trails, hasLength(expected.length));

    for (var i = 0; i < trails.length; i++) {
      expect(_trailKey(trails[i]), _trailKey(expected[i]));
    }
  });

  test('loadTrails elevation round-trip: высоты доезжают до native (A1)',
      () async {
    // Гемилер: GeoJSON пуст — сидер берёт GPX с <ele>; высоты
    // обязаны сохраниться через БД (схема v4).
    final gemiler =
        await const MapDataRepository(islandId: 'gemiler').loadTrails();

    final gemilerElevations = gemiler
        .expand((trail) => trail.points)
        .map((point) => point.elevation)
        .whereType<double>()
        .toList();

    expect(
      gemilerElevations,
      isNotEmpty,
      reason: 'GPX с <ele> должен дать высоты через сидер и БД',
    );

    // Анталья: GeoJSON с 3-й координатой — высоты из GeoJSON.
    final antalya =
        await const MapDataRepository(islandId: 'antalya').loadTrails();

    final antalyaElevations = antalya
        .expand((trail) => trail.points)
        .map((point) => point.elevation)
        .whereType<double>()
        .toList();

    expect(
      antalyaElevations,
      isNotEmpty,
      reason: 'GeoJSON [lon, lat, ele] должен дать высоты (A1)',
    );

    // Сверка с прямым парсингом: максимальная высота БД == GPX.
    final gpxRaw =
        await rootBundle.loadString('content/fethiye/gemiler/trails.gpx');

    final gpxEles = RegExp(r'<ele>([0-9.]+)</ele>')
        .allMatches(gpxRaw)
        .map((m) => double.parse(m.group(1)!))
        .toList();

    final dbMax = gemiler
        .expand((trail) => trail.points)
        .map((point) => point.elevation)
        .whereType<double>()
        .reduce((a, b) => a > b ? a : b);

    expect(dbMax, gpxEles.reduce((a, b) => a > b ? a : b));
  });

  test('loadTrails kekova: пустой GeoJSON без зарегистрированного GPX', () async {
    // У kekova GPX не зарегистрирован в ассетах — сидер кладёт
    // маршруты только из GeoJSON, а он пуст. Регресс-проверка
    // единого порядка «geojson-first»: пустой GeoJSON — фолбэк на
    // отсутствующий GPX, итог — пустой список без исключений.
    final trails =
        await const MapDataRepository(islandId: 'kekova').loadTrails();

    final raw =
        await rootBundle.loadString('content/lykia/kekova/trails.geojson');

    final expected = parseTrailsGeoJson(raw);

    expect(trails, hasLength(expected.length));
    expect(trails, isEmpty);
  });

  test('loadPois сортировка: пронумерованные по возрастанию, затем без номера',
      () async {
    final pois = await const MapDataRepository(islandId: 'gemiler').loadPois();

    final numbered = pois.takeWhile((p) => p.number != null).toList();

    final unnumbered = pois.skipWhile((p) => p.number != null).toList();

    for (var i = 1; i < numbered.length; i++) {
      expect(numbered[i].number!, greaterThan(numbered[i - 1].number!));
    }

    expect(unnumbered.every((p) => p.number == null), isTrue);

    // Без номера — в порядке следования в poi.json.
    final raw = await rootBundle.loadString('content/fethiye/gemiler/poi.json');

    final fileOrder = (jsonDecode(raw) as List<dynamic>)
        .whereType<Map<String, dynamic>>()
        .map((m) => m['id'] as String)
        .toList();

    final fileOrderUnnumbered = fileOrder
        .where((id) => unnumbered.any((p) => p.id == id))
        .toList();

    expect(unnumbered.map((p) => p.id).toList(), fileOrderUnnumbered);
  });
}

List<String> _poiKeys(List<Poi> pois) {

  return pois
      .map(
        (p) => '${p.id}|${p.title}|${p.latitude}|${p.longitude}|'
            '${p.radius}|${p.description}|${p.audioPath}|${p.videoPath}|'
            '${p.imagePaths.join(',')}|${p.trailIds.join(',')}|'
            '${p.category}|${p.number}',
      )
      .toList()
    ..sort();
}

String _trailKey(Trail t) {

  return '${t.id}|${t.name}|${t.description}|${t.distance}|'
      '${t.imagePaths.join(',')}|'
      '${t.lines?.map((line) => line.map(_pointKey).join(';')).join('|') ?? '-'}|'
      '${t.points.map(_pointKey).join(';')}';
}

String _pointKey(TrailPoint p) {

  return '${p.id}@${p.order}@${p.latitude}@${p.longitude}';
}