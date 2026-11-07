// P0-2 (7-й проход): отступ «под капсулу» у модальных шторок —
// только там, где капсула реально есть. Шторка, открытая со
// страницы шелла (главная), лежит ПОД капсулой — низ контента
// обязан заканчиваться выше неё. Шторка с той же кнопки, но
// открытая со страницы деталей (root-навигатор НАД капсулой),
// раньше получала лишние ~74 px снизу.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:island_guide/app/app.dart';
import 'package:island_guide/features/content/models/region_catalog.dart';
import 'package:island_guide/features/content/providers/content_providers.dart';
import 'package:island_guide/features/navigation/presentation/tree_navigation_button.dart';

import 'support/lazy_scroll.dart';
import 'support/test_database.dart';

void main() {
  initTestDatabase();

  testWidgets(
    'шторка дерева: отступ капсулы в шелле есть, из деталей — нет',
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

      // Контент всех локаций — в реальной асинхронности
      // (паттерн tree_navigation_test).
      await tester.runAsync(() async {
        await container.read(regionsProvider.future);
        await container.read(islandsProvider.future);

        for (final id in kLocationIds) {
          await container.read(trailsFamily(id).future);
          await container.read(poisFamily(id).future);
        }
      });

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const IslandGuideApp(),
        ),
      );

      // Сплэш → главная.
      await tester.pumpAndSettle();
      await tester.pumpAndSettle();

      double sheetScrollBottomPadding() {
        final scroll = tester.widget<SingleChildScrollView>(
          find.byWidgetPredicate(
            (w) =>
                w is SingleChildScrollView &&
                w.padding is EdgeInsets &&
                (w.padding as EdgeInsets).left == 10,
          ),
        );

        return (scroll.padding as EdgeInsets).bottom;
      }

      // --- Шторка из шелла (главная): капсула под ней — есть отступ.
      await tester.ensureVisible(find.byType(TreeNavigationButton).first);
      await tester.tap(find.byType(TreeNavigationButton).first);
      await tester.pumpAndSettle();

      expect(find.byTooltip('Закрыть'), findsOneWidget);
      expect(
        sheetScrollBottomPadding(),
        86,
        reason: 'шторка из шелла лежит под капсулой: низ контента выше неё',
      );

      await tester.tap(find.byTooltip('Закрыть'));
      await tester.pumpAndSettle();

      // --- Переход на страницу деталей POI (root-навигатор).
      await scrollLazyUntilVisible(
        tester,
        find.text('Соборная базилика'),
      );

      // Ленивый скролл гарантирует только ПОСТРОЕНИЕ элемента
      // (cacheExtent) — доскролливаем его в видимую зону, иначе
      // тап уходит в превью карты под списком.
      await tester.ensureVisible(find.text('Соборная базилика'));

      await tester.pumpAndSettle();

      await tester.tap(find.text('Соборная базилика'));
      await tester.pumpAndSettle();
      await tester.pumpAndSettle();

      // --- Та же шторка, но из деталей: капсулы под ней нет.
      await tester.tap(find.byType(TreeNavigationButton).first);
      await tester.pumpAndSettle();

      expect(find.byTooltip('Закрыть'), findsOneWidget);
      expect(
        sheetScrollBottomPadding(),
        24,
        reason: 'шторка с root-навигатора лежит НАД капсулой: '
            'лишнего отступа быть не должно (P0-2)',
      );
    },
  );
}
