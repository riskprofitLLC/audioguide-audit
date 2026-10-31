// A2 (10-й проход): фильтры результатов поиска.
//
// 1. При выбранном фильтре без совпадений (а по запросу в других
//    видах они есть) ряд чипов остаётся на экране + компактная
//    заглушка «В этом разделе совпадений нет» — раньше голое
//    «Ничего не найдено» без чипов замыкало пользователя в
//    пустом фильтре.
// 2. Смена запроса сбрасывает фильтр в «Всё».

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:island_guide/app/app.dart';
import 'package:island_guide/features/content/providers/content_providers.dart';
import 'package:island_guide/features/navigation/presentation/tree_navigation_button.dart';
import 'package:island_guide/features/search/providers/search_providers.dart';

import 'support/test_database.dart';

void main() {
  initTestDatabase();

  testWidgets(
    'пустой фильтр не прячет чипы; смена запроса сбрасывает фильтр (A2)',
    (WidgetTester tester) async {
      final container = ProviderContainer(
        overrides: [
          currentIslandIdProvider.overrideWith((_) => 'gemiler'),
        ],
      );

      addTearDown(container.dispose);

      // Грузим только то, что реально нужно шторке: манифесты,
      // индекс и контент ТЕКУЩЕЙ локации (A6 — остальные локации
      // дерева свёрнуты и их провайдеры не читаются).
      await tester.runAsync(() async {
        await container.read(regionsProvider.future);
        await container.read(islandsProvider.future);
        await container.read(searchIndexProvider.future);
        await container.read(poisFamily('gemiler').future);
        await container.read(trailsFamily('gemiler').future);
      });

      rootBundle.clear();

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const IslandGuideApp(),
        ),
      );

      // Сплэш → главная.
      await tester.pumpAndSettle();
      await tester.pumpAndSettle();

      final treeButton = find.byType(TreeNavigationButton);

      await tester.ensureVisible(treeButton);
      await tester.tap(treeButton);
      await tester.pumpAndSettle();

      final searchField = find.byType(TextField);

      // «маяк» — совпадения только в «Местах» (poi-09 Гемилера,
      // маяки Кековы-побережья и Гелидоньи).
      await tester.enterText(searchField, 'маяк');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 220));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('search-poi-gemiler-poi-09')),
        findsOneWidget,
        reason: 'по «маяк» находится POI Гемилера',
      );

      // B1 (10-й проход): тап-цели ≥ 44 — чипы фильтров и кнопки
      // шапки дерева (иконки остаются маленькими, зона растёт).
      final chipRect = tester.getRect(
        find.byKey(const ValueKey('search-filter-places')),
      );

      expect(chipRect.height, greaterThanOrEqualTo(44),
          reason: 'тап-цель чипа-фильтра не ниже 44');

      final clearRect = tester.getRect(find.byTooltip('Очистить поиск'));

      expect(clearRect.height, greaterThanOrEqualTo(44),
          reason: 'тап-цель «Очистить поиск» не ниже 44');

      expect(clearRect.width, greaterThanOrEqualTo(44));

      final closeRect = tester.getRect(find.byTooltip('Закрыть'));

      expect(closeRect.height, greaterThanOrEqualTo(44),
          reason: 'тап-цель «Закрыть» не ниже 44');

      // Чип «Локации»: в этом виде совпадений нет — но чипы
      // остаются, и заглушка — компактная, не «Ничего не найдено».
      await tester.tap(find.byKey(const ValueKey('search-filter-locations')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('search-filter-locations')),
        findsOneWidget,
        reason: 'ряд чипов-фильтров не исчезает в пустой выдаче',
      );

      expect(find.text('В этом разделе совпадений нет'), findsOneWidget);

      expect(find.text('Ничего не найдено'), findsNothing,
          reason: 'совпадения по запросу есть — это не пустой поиск');

      // Возврат в «Места» — результаты на месте.
      await tester.tap(find.byKey(const ValueKey('search-filter-places')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('search-poi-gemiler-poi-09')),
        findsOneWidget,
      );

      // Смена запроса сбрасывает фильтр в «Всё»: «гемилер» находит
      // и локацию, и POI — без ручного возврата чипа «Всё».
      await tester.enterText(searchField, 'гемилер');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 220));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('search-location-gemiler')),
        findsOneWidget,
        reason: 'фильтр сброшен в «Всё» — локация видна сразу',
      );

      expect(
        find.byKey(const ValueKey('search-poi-gemiler-poi-01')),
        findsOneWidget,
      );
    },
  );
}
