// Бенчмарк навигации по треку на самом большом текущем маршруте.
//
// TrailNavigator.update() на каждую GPS-позицию линейно проходит по
// всем точкам маршрута. Тест замеряет время одного update() на треке
// Гемилера (~90 точек, самый большой маршрут проекта) и держит
// регрессионный порог: если навигатор начнёт деградировать (например,
// из-за квадратичного алгоритма), тест это поймает.

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:island_guide/features/content/services/geojson_trails_parser.dart';
import 'package:island_guide/features/gps/models/user_position.dart';
import 'package:island_guide/features/gps/services/trail_navigator.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'TrailNavigator.update на треке Гемилера не деградирует со временем',
    () async {
      final raw = await rootBundle.loadString(
        'content/fethiye/gemiler/trails.geojson',
      );

      final trails = parseTrailsGeoJson(raw);

      expect(trails, isNotEmpty);

      // Самый длинный маршрут проекта.
      final trail = trails.reduce(
        (a, b) => a.points.length >= b.points.length ? a : b,
      );

      expect(
        trail.points.length,
        greaterThanOrEqualTo(80),
        reason: 'Трек Гемилера — носитель бенчмарка; '
            'если он поменялся, пересмотри порог',
      );

      final navigator = TrailNavigator();

      // Точка на маршруте, чтобы гарантированно искать проекцию.
      final onTrack = UserPosition(
        latitude: trail.points.first.latitude,
        longitude: trail.points.first.longitude,
      );

      // Прогрев: первая итерация (JIT, инициализация логгера).
      navigator.update(onTrack, [trail]);

      const iterations = 200;

      final watch = Stopwatch()..start();

      for (var i = 0; i < iterations; i++) {
        navigator.update(onTrack, [trail]);
      }

      watch.stop();

      final perCallUs =
          watch.elapsedMicroseconds / iterations;

      // Прогон на этой машине ~85 мкс на ~90 точек (включая AppLogger);
      // под параллельной нагрузкой полного `flutter test` — до ~300 мкс.
      // Порог с запасом ~10x, чтобы не флакать на слабой CI, но ловить
      // деградацию на порядок (например, вложенный цикл по всем точкам
      // в каждом сегменте даст ~8 мс — тест упадёт).
      expect(
        perCallUs,
        lessThan(1000),
        reason: 'update() на ~90 точках занял '
            '${perCallUs.toStringAsFixed(1)} мкс в среднем — '
            'проверь сложность алгоритма',
      );
    },
  );
}