// A6 (8-й проход): семантика дерева навигации.
//
// Строки региона/локации/маршрута — кнопки с состоянием
// «развёрнуто/свёрнуто»; кнопка-стрелка перехода — отдельный узел
// с подписью «Открыть …». Скринридер различает тап по строке
// (свернуть/развернуть) и переход к объекту.
//
// Отдельный файл: контент всех локаций грузится в runAsync —
// второго контент-теста в файле быть не может (см. AGENTS.md).

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:island_guide/app/app.dart';
import 'package:island_guide/features/content/models/region_catalog.dart';
import 'package:island_guide/features/content/providers/content_providers.dart';
import 'package:island_guide/features/navigation/presentation/tree_navigation_button.dart';

import 'support/test_database.dart';

void main() {
  initTestDatabase();

  testWidgets(
    'узлы дерева: button + expanded, стрелка — отдельная кнопка (A6)',
    (WidgetTester tester) async {
      final handle = tester.ensureSemantics();

      final container = ProviderContainer(
        overrides: [
          currentIslandIdProvider.overrideWith((_) => 'gemiler'),
        ],
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

      // Открываем дерево навигации с главной.
      final treeButton = find.byType(TreeNavigationButton);

      await tester.ensureVisible(treeButton);
      await tester.tap(treeButton);
      await tester.pumpAndSettle();

      // --- Строка региона: кнопка + состояние «свёрнуто» (по умолчанию). ---
      final regionRow = find.byKey(const ValueKey('tree-region-fethiye'));

      expect(regionRow, findsOneWidget);

      final regionData =
          tester.getSemantics(regionRow).getSemanticsData();

      expect(
        regionData.flagsCollection.isButton,
        isTrue,
        reason: 'строка региона — кнопка для скринридера',
      );

      expect(
        regionData.flagsCollection.isExpanded.toBoolOrNull(),
        isFalse,
        reason: 'регион свёрнут по умолчанию — состояние видно скринридеру',
      );

      expect(
        regionData.label.contains('Залив Фетхие'),
        isTrue,
        reason: 'название региона входит в подпись узла',
      );

      // Раскрываем регион тапом — состояние становится «развёрнуто».
      await tester.ensureVisible(regionRow);
      await tester.tap(regionRow);
      await tester.pumpAndSettle();

      expect(
        tester.getSemantics(regionRow).getSemanticsData()
            .flagsCollection.isExpanded.toBoolOrNull(),
        isTrue,
        reason: 'после раскрытия узел сообщает «развёрнуто»',
      );

      // --- Строка локации: кнопка, свёрнута по умолчанию. ---
      final locationRow =
          find.byKey(const ValueKey('tree-fethiye/gemiler'));

      expect(locationRow, findsOneWidget);

      final locationData =
          tester.getSemantics(locationRow).getSemanticsData();

      expect(locationData.flagsCollection.isButton, isTrue);
      expect(
        locationData.flagsCollection.isExpanded.toBoolOrNull(),
        isFalse,
        reason: 'локация свёрнута по умолчанию',
      );

      // Раскрываем локацию — видна кнопка-стрелка перехода.
      await tester.ensureVisible(locationRow);
      await tester.tap(locationRow);
      await tester.pumpAndSettle();

      expect(
        tester.getSemantics(locationRow).getSemanticsData()
            .flagsCollection.isExpanded.toBoolOrNull(),
        isTrue,
      );

      // --- Кнопка-стрелка перехода: отдельный узел с действием. ---
      final openButton =
          find.byKey(const ValueKey('tree-fethiye/gemiler/open'));

      expect(openButton, findsOneWidget);

      // Стрелка — отдельная КНОПКА с подписью «Открыть локацию …»:
      // скринридер различает строку (свернуть/развернуть) и
      // переход к объекту.
      final openNode = find.bySemanticsLabel(
        'Открыть локацию Гемилер',
      );

      expect(openNode, findsOneWidget);

      final openData =
          tester.getSemantics(openNode).getSemanticsData();

      expect(openData.flagsCollection.isButton, isTrue);

      // --- Тап по строке региона сворачивает его: состояние меняется. ---
      await tester.ensureVisible(regionRow);

      await tester.tap(regionRow);
      await tester.pumpAndSettle();

      final collapsedData =
          tester.getSemantics(regionRow).getSemanticsData();

      expect(
        collapsedData.flagsCollection.isExpanded.toBoolOrNull(),
        isFalse,
        reason: 'после сворачивания узел больше не сообщает '
            'состояние «развёрнуто»',
      );

      handle.dispose();
    },
  );
}
