// Интеграционный тест: реальный GPX-пакет острова парсится.

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:island_guide/features/content/services/gpx_trails_parser.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('content/fethiye/gemiler/trails.gpx парсируется как сеть из 4 веток', () async {

    final raw = await rootBundle.loadString(
      'content/fethiye/gemiler/trails.gpx',
    );

    final trails = parseTrailsGpx(raw);

    expect(trails, hasLength(1));

    final trail = trails.single;

    expect(trail.id, 'trail-01');
    // 4 ветки: основная + 2 боковых дороги + закругление к «Погосту»
    // (радиус ~60 м, касается основной в одной точке, не пересекает).
    expect(trail.lines, hasLength(4));
    expect(trail.points, hasLength(97));

    final covered = <String>{};
    for (final branch in trail.segments) {
      for (final p in branch) {
        covered.add('${p.latitude},${p.longitude}');
      }
    }
    // 94 уникальных (97 всего): 3 точки-стыка дорог присутствуют
    // в двух ветках; ответвление к «Погосту» не делит точек с основной.
    expect(covered, hasLength(94));
  });
}
