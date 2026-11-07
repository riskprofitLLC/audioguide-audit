// buildHomeModel (D5/R3): группировка главной вынесена из HomePage
// в чистую функцию — юнит-тесты без виджетов.

import 'package:flutter_test/flutter_test.dart';

import 'package:island_guide/features/home/models/home_model.dart';
import 'package:island_guide/features/poi/models/poi.dart';
import 'package:island_guide/features/trails/models/trail.dart';
import 'package:island_guide/features/trails/models/trail_point.dart';

Poi _poi(String id, int? number, [List<String> trails = const []]) => Poi(
      id: id,
      title: id,
      latitude: 36.6,
      longitude: 29.1,
      number: number,
      trailIds: trails,
    );

Trail _trail(String id) => Trail(
      id: id,
      name: id,
      points: const [
        TrailPoint(id: 'p1', latitude: 36.6, longitude: 29.1, order: 1),
      ],
    );

void main() {
  test('группировка: маршрутные точки в маршруте, остальные — вне маршрута', () {
    final pois = [
      _poi('poi-02', 2, ['trail-01']),
      _poi('poi-01', 1, ['trail-01']),
      _poi('poi-10', null),
      _poi('poi-11', null, ['trail-02']),
    ];

    final model = buildHomeModel(pois, [_trail('trail-01'), _trail('trail-02')]);

    // sortedPois — по номеру маршрута.
    expect(model.sortedPois.map((p) => p.id), ['poi-01', 'poi-02', 'poi-10', 'poi-11']);

    // Точки маршрута в порядке номеров.
    final t1 = model.trailsWithPois.firstWhere((t) => t.trail.id == 'trail-01');

    expect(t1.allPois.map((p) => p.id), ['poi-01', 'poi-02']);

    // Вnemаршрутные — только без trailIds.
    expect(model.orphanPois.map((p) => p.id), ['poi-10']);

    // Маршрут без точек тоже в списке.
    expect(model.trailsWithPois.length, 2);
  });

  test('записи списка плоские и типизированные', () {
    const entries = <HomeEntry>[
      GapEntry(16),
      EmptyTrailEntry(message: 'пусто'),
    ];

    expect(entries[0], isA<GapEntry>());
    expect((entries[1] as EmptyTrailEntry).message, 'пусто');
  });
}
