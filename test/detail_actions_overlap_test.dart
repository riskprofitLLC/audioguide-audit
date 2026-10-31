// P0-5 (7-й проход): плавающие кнопки «дерево»+«избранное» на
// страницах деталей (top: 8, right: 16) раньше накладывались на
// правую колонку wide-раскладки (900–1100 px): бейджи и заголовок
// попадали под кнопки. Правая колонка обязана начинаться ниже
// зоны кнопок (отступ сверху ≥ 64).
//
// Один контент-тест на файл: poiFullTextProvider читает тексты
// через rootBundle.loadString — во втором тесте файла Future под
// FakeAsync не завершается (см. AGENTS.md, Testing).

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:island_guide/features/content/providers/content_providers.dart';
import 'package:island_guide/features/poi/presentation/pages/poi_detail_page.dart';
import 'package:island_guide/features/trails/presentation/pages/trail_detail_page.dart';

import 'support/test_database.dart';

void main() {
  initTestDatabase();

  testWidgets(
    'плавающие кнопки не пересекают правую колонку на 900–1100',
    (tester) async {
      final container = ProviderContainer(
        overrides: [
          currentIslandIdProvider.overrideWith((_) => 'gemiler'),
        ],
      );

      addTearDown(container.dispose);
      addTearDown(tester.view.reset);

      // Контент Гемилера — в реальной асинхронности (паттерн
      // tree_navigation_test, см. AGENTS.md).
      await tester.runAsync(() async {
        await container.read(poisFamily('gemiler').future);
        await container.read(trailsFamily('gemiler').future);
      });

      rootBundle.clear();

      // Обе страницы деталей прогоняются в одном тесте: poi-06 —
      // с бейджами номера/категории, trail-01 — с бейджами
      // маршрута (у него правая колонка тоже доходит до кромки).
      final pages = <Widget>[
        const PoiDetailPage(
          poiId: 'poi-06',
          islandId: 'gemiler',
        ),
        const TrailDetailPage(
          trailId: 'trail-01',
          islandId: 'gemiler',
        ),
      ];

      for (final page in pages) {
        final app = UncontrolledProviderScope(
          container: container,
          child: MaterialApp(home: page),
        );

        for (final width in [900.0, 1024.0, 1100.0]) {
          tester.view.physicalSize = Size(width, 900);
          tester.view.devicePixelRatio = 1.0;

          await tester.pumpWidget(app);
          await tester.pumpAndSettle();

          final actions = tester.getRect(
            find.byKey(const ValueKey('detail-floating-actions')),
          );

          final badges = tester.getRect(
            find.byKey(const ValueKey('detail-badges')),
          );

          final overlaps = actions.right >= badges.left &&
              actions.left <= badges.right &&
              actions.bottom >= badges.top &&
              actions.top <= badges.bottom;

          expect(
            overlaps,
            isFalse,
            reason: 'на ширине $width кнопки сверху справа не должны '
                'пересекаться с бейджами правой колонки (P0-5)',
          );
        }
      }
    },
  );
}
