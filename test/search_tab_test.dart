// Вкладка «Поиск» (P0-1, 6-й проход): после закрытия шторки
// адрес возвращается к обычному /map (подсвечена «Карта»), а
// повторный тап по «Поиск» открывает шторку заново. Раньше
// адрес застревал на /map?search=1, вкладка «Поиск» оставалась
// подсвеченной, и повторный тап ничего не делал
// (index == selectedIndex → return).

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:island_guide/app/app.dart';
import 'package:island_guide/app/router.dart';
import 'package:island_guide/features/content/models/region_catalog.dart';
import 'package:island_guide/features/content/providers/content_providers.dart';

import 'support/test_database.dart';

void main() {
  initTestDatabase();

  // Пачка фиксированных прокачек: карта под FakeAsync не
  // «устаканивается» (стиль грузит ассеты), pumpAndSettle виснет —
  // качаем кадры шагами, как router_tabs_test.
  Future<void> pumpFrames(WidgetTester tester, int times) async {
    for (var i = 0; i < times; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets(
    'закрытие шторки поиска возвращает «Карту», повторный тап открывает снова',
    (tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;

      addTearDown(tester.view.reset);

      final container = ProviderContainer(
        overrides: [
          currentIslandIdProvider.overrideWith((_) => 'gemiler'),
        ],
      );

      addTearDown(container.dispose);

      // Контент всех локаций грузим в реальной асинхронности —
      // паттерн tree_navigation_test (см. AGENTS.md).
      await tester.runAsync(() async {
        await container.read(regionsProvider.future);
        await container.read(islandsProvider.future);

        for (final id in kLocationIds) {
          await container.read(trailsFamily(id).future);
          await container.read(poisFamily(id).future);
        }
      });

      rootBundle.clear();

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const IslandGuideApp(),
        ),
      );

      // Сплэш 900 мс → /home.
      await tester.pump(const Duration(milliseconds: 1200));
      await pumpFrames(tester, 3);

      final router = AppRouter.router;

      NavigationBar bar() =>
          tester.widget<NavigationBar>(find.byType(NavigationBar));

      expect(bar().selectedIndex, 0, reason: 'старт — вкладка «Главная»');

      // Тап по «Поиск»: адрес /map?search=1, шторка открыта,
      // подсвечена вкладка «Поиск».
      await tester.tap(find.text('Поиск'));
      await pumpFrames(tester, 5);

      expect(
        router.routerDelegate.currentConfiguration.uri.queryParameters['search'],
        '1',
      );

      expect(find.byTooltip('Закрыть'), findsOneWidget,
          reason: 'шторка поиска открыта');

      expect(bar().selectedIndex, 3, reason: 'подсвечена вкладка «Поиск»');

      // Закрываем шторку: адрес возвращается к обычному /map,
      // подсвечена вкладка «Карта» — вкладка «Поиск» не залипает.
      await tester.tap(find.byTooltip('Закрыть'));
      await pumpFrames(tester, 6);

      final uri = router.routerDelegate.currentConfiguration.uri;

      expect(uri.path, '/map');
      expect(uri.queryParameters['search'], isNull,
          reason: 'search=1 убран из адреса после закрытия шторки');

      expect(bar().selectedIndex, 1,
          reason: 'после закрытия шторки подсвечена вкладка «Карта»');

      expect(find.byTooltip('Закрыть'), findsNothing,
          reason: 'шторка закрыта');

      // Повторный тап по «Поиск» открывает шторку снова — раньше
      // здесь ничего не происходило (index == selectedIndex).
      await tester.tap(find.text('Поиск'));
      await pumpFrames(tester, 5);

      expect(find.byTooltip('Закрыть'), findsOneWidget,
          reason: 'повторный тап по «Поиск» открывает шторку заново');

      expect(
        router.routerDelegate.currentConfiguration.uri
            .queryParameters['search'],
        '1',
      );

      expect(bar().selectedIndex, 3);
    },
  );
}
