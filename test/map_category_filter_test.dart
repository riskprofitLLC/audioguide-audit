// 14-й проход: фильтр категорий на карте СВЁРНУТ в кнопку
// (низ-лево); по тапу разворачивается лентой чипов, выбор
// категории применяет фильтр к MapWidget и сворачивает ленту
// обратно. Развёрнутая лента не заезжает под блок контролов
// (GPS + «+ / −»).
//
// Контентный тест — ОДИН на файл (rootBundle под FakeAsync).

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:island_guide/features/content/providers/content_providers.dart';
import 'package:island_guide/features/map/presentation/pages/map_page.dart';
import 'package:island_guide/features/map/presentation/widgets/map_widget.dart';
import 'package:island_guide/features/map/providers/map_provider.dart';

import 'support/test_database.dart';

void main() {
  initTestDatabase();

  testWidgets('фильтр категорий: кнопка → лента → выбор (14-й проход)',
      (tester) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1.0;

    addTearDown(tester.view.reset);

    final container = ProviderContainer(
      overrides: [
        currentIslandIdProvider.overrideWith((_) => 'gemiler'),
        regionMapStyleFamily('fethiye').overrideWith(
          (ref) async => '{"version":8,"sources":{},"layers":[]}',
        ),
      ],
    );

    addTearDown(container.dispose);

    await tester.runAsync(() async {
      await container.read(regionsProvider.future);
      await container.read(islandsProvider.future);
      await container.read(trailsFamily('gemiler').future);
      await container.read(poisFamily('gemiler').future);
    });

    rootBundle.clear();

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: MapPage(
            islandId: 'gemiler',
            lat: 36.55,
            lng: 29.07,
            zoom: 14,
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // По умолчанию лента СВЁРНУТА: только кнопка-тумблер.
    final toggle = find.byKey(const ValueKey('map-filter-toggle'));

    expect(toggle, findsOneWidget, reason: 'кнопка фильтра на карте');

    // Свернутая лента уезжает за левый край (AnimatedSlide
    // offset -1) и не ловит тапы — виджет в дереве, но невидим.
    Offset railOffset() => tester
        .widget<AnimatedSlide>(
          find.descendant(
            of: find.byKey(const ValueKey('map-category-rail')),
            matching: find.byType(AnimatedSlide),
          ),
        )
        .offset;

    expect(railOffset(), const Offset(-1, 0), reason: 'лента свёрнута');

    expect(
      tester.widget<MapWidget>(find.byType(MapWidget)).categoryFilter,
      isNull,
    );

    // Разворачиваем ленту.
    await tester.tap(toggle);
    await tester.pumpAndSettle();

    expect(railOffset(), Offset.zero, reason: 'лента развёрнута');
    expect(find.text('Все'), findsOneWidget);
    expect(find.text('Маяк'), findsOneWidget);

    // Развёрнутая лента не заезжает под блок контролов зума:
    // правый край ленты левее кнопки GPS (правый блок right:16).
    final railRect = tester.getRect(
      find.byKey(const ValueKey('map-category-rail')),
    );

    final gpsRect = tester.getRect(
      find.byTooltip('Моё местоположение'),
    );

    final zoomInRect = tester.getRect(find.byTooltip('Приблизить'));

    expect(
      railRect.right,
      lessThanOrEqualTo(gpsRect.left),
      reason: 'лента не пересекает кнопку GPS (14-й проход)',
    );

    expect(
      railRect.right,
      lessThanOrEqualTo(zoomInRect.left),
      reason: 'лента не пересекает пилюлю «+ / −»',
    );

    // Выбираем «Церковь»: чип может быть за краем прокрутки —
    // подводим (паттерн ensureVisible из тестов дерева).
    await tester.ensureVisible(find.text('Церковь'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Церковь'));
    await tester.pumpAndSettle();

    expect(
      tester.widget<MapWidget>(find.byType(MapWidget)).categoryFilter,
      'church',
      reason: 'выбранная категория прокидывается в MapWidget (1c)',
    );

    // Выбор сворачивает ленту: на кнопке — точка активного
    // фильтра.
    expect(railOffset(), const Offset(-1, 0), reason: 'лента свернулась');

    // Повторный тап — фильтр сбрасывается «Все».
    await tester.tap(toggle);
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Все'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Все'));
    await tester.pumpAndSettle();

    expect(
      tester.widget<MapWidget>(find.byType(MapWidget)).categoryFilter,
      isNull,
      reason: '«Все» сбрасывает фильтр (1c)',
    );
  });
}
