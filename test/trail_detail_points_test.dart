// Страница маршрута показывает СВОИ точки.
//
// Раньше страница заканчивалась описанием и картой: под ними
// оставалась пустота, а списка «из чего состоит маршрут» не было
// вовсе — пользователь не мог перейти к точкам маршрута со
// страницы маршрута.
//
// Один контент-тест на файл: poi.json грузится через rootBundle
// в runAsync (см. AGENTS.md, Testing).

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:island_guide/features/content/providers/content_providers.dart';
import 'package:island_guide/features/poi/presentation/widgets/poi_list_tile.dart';
import 'package:island_guide/features/trails/presentation/pages/trail_detail_page.dart';

import 'support/test_database.dart';

void main() {
  initTestDatabase();

  testWidgets('страница маршрута: секция «Точки маршрута» со всеми точками',
      (tester) async {
    // Телефонная ширина: одноколоночная раскладка, список не ленивый
    // (Column внутри ListView) — плитки строятся все.
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1.0;

    addTearDown(tester.view.reset);

    final container = ProviderContainer(
      overrides: [
        currentIslandIdProvider.overrideWith((_) => 'gemiler'),
      ],
    );

    addTearDown(container.dispose);

    await tester.runAsync(() async {
      await container.read(poisFamily('gemiler').future);
      await container.read(trailsFamily('gemiler').future);
    });

    rootBundle.clear();

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: TrailDetailPage(
            trailId: 'trail-01',
            islandId: 'gemiler',
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Точки маршрута'), findsOneWidget,
        reason: 'на странице маршрута появился список его точек');

    // Маршрут Гемилера: 10 точек (poi-01..poi-10).
    expect(find.byType(PoiListTile), findsNWidgets(10));

    // Первая точка маршрута видна и названа.
    expect(find.text('Вход на остров Гемилер'), findsOneWidget);
  });
}
