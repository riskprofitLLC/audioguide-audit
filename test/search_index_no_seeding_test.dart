// A10.2 (8-й проход): поиск не будит контентные провайдеры локаций.
//
// Раньше _SearchResults при первом запросе подписывался на
// trailsFamily/poisFamily ВСЕХ 9 локаций — на native это холодный
// сидинг всех пакетов. Теперь данные — готовый компактный индекс
// (tool/build_search_index.py → searchIndexProvider).
//
// Детектор: ProviderObserver фиксирует создание членов семей
// poisFamily/trailsFamily. Дерево (в той же шторке) создаёт их
// легально — сам каталог; поиск не должен добавлять новых ПОСЛЕ
// ввода запроса.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:island_guide/app/app.dart';
import 'package:island_guide/features/content/models/region_catalog.dart';
import 'package:island_guide/features/content/providers/content_providers.dart';
import 'package:island_guide/features/navigation/presentation/tree_navigation_button.dart';

import 'support/test_database.dart';

/// Запоминает, какие контентные провайдеры создавались.
///
/// У членов семей в Riverpod 2 имя пустое — различаем по типу:
/// `FutureProvider<List<Poi>>` — это poisFamily(локация) (единственный
/// POI-семейство в приложении; его несемейный двойник poisProvider
/// уже создан главной и в подсчёт «новых» не попадает).
class _FamilySpy extends ProviderObserver {
  final List<String> created = [];

  @override
  void didAddProvider(
    ProviderBase<Object?> provider,
    Object? value,
    ProviderContainer container,
  ) {
    final type = provider.runtimeType.toString();

    if (type.contains('FutureProvider<List<Poi>>')) {
      created.add('pois');
    } else if (type.contains('FutureProvider<List<Trail>>')) {
      created.add('trails');
    } else if (type.contains('MapDataRepository')) {
      created.add('repo');
    }
  }
}

void main() {
  initTestDatabase();

  testWidgets(
    'поиск по индексу не создаёт контентные провайдеры локаций (A10.2)',
    (WidgetTester tester) async {
      final spy = _FamilySpy();

      final container = ProviderContainer(
        overrides: [
          currentIslandIdProvider.overrideWith((_) => 'gemiler'),
        ],
        observers: [spy],
      );

      addTearDown(container.dispose);

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

      await tester.pumpAndSettle();
      await tester.pumpAndSettle();

      final treeButton = find.byType(TreeNavigationButton);

      await tester.ensureVisible(treeButton);
      await tester.tap(treeButton);
      await tester.pumpAndSettle();

      // Дерево отрисовано: легитимные подписки уже есть.
      final createdByTree = spy.created.length;

      expect(createdByTree, greaterThan(0));

      // Вводим запрос — результаты строятся ПО ИНДЕКСУ.
      final searchField = find.byType(TextField);

      expect(searchField, findsOneWidget);

      await tester.enterText(searchField, 'маяк');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 220));

      // Индекс грузится через rootBundle — даём завершиться.
      await tester.pumpAndSettle();

      // Результаты есть: POI «Маяк» Гемилера и маяки других
      // локаций из ИНДЕКСА.
      expect(
        find.byKey(const ValueKey('search-poi-gemiler-poi-09')),
        findsOneWidget,
        reason: 'поиск находит POI по названию',
      );

      // НИ ОДНОГО нового контентного провайдера при поиске:
      // ни сидинга, ни чтения poi.json всех локаций.
      expect(
        spy.created.length,
        createdByTree,
        reason: 'поиск читает готовый индекс и не подписывается '
            'на poisFamily/trailsFamily локаций',
      );

      // Пустой результат — тоже без новых провайдеров.
      await tester.enterText(searchField, 'никогданесуществует');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 220));
      await tester.pumpAndSettle();

      expect(find.text('Ничего не найдено'), findsOneWidget);
      expect(
        find.text('По запросу «никогданесуществует» совпадений нет'),
        findsOneWidget,
      );

      expect(spy.created.length, createdByTree);
    },
  );
}
