// Regression-тест A1 (8-й проход): hero-тег внемаршрутной плитки
// живёт после прокрутки туда-обратно. Отдельный файл: контентные
// widget-тесты грузят poi.json, второго контент-теста в файле
// под FakeAsync быть не может (см. AGENTS.md, Testing).

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:island_guide/features/content/providers/content_providers.dart';
import 'package:island_guide/features/home/presentation/home_page.dart';

import 'support/lazy_scroll.dart';
import 'support/test_database.dart';

void main() {

  initTestDatabase();

  testWidgets(
    'Hero-тег внемаршрутной плитки живёт после прокрутки туда-обратно',
    (WidgetTester tester) async {
      // A1, 8-й проход: heroSeen заполнялся побочным эффектом внутри
      // ленивого itemBuilder — плитка «Вне маршрута» при повторном
      // построении (после ухода из вьюпорта и возврата) получала
      // null вместо тега, и полёт миниатюры в детали молчал.
      final container = ProviderContainer(
        overrides: [
          currentIslandIdProvider.overrideWith((_) => 'gemiler'),
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
            home: HomePage(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      final orphanHero = find.byWidgetPredicate(
        (w) => w is Hero && w.tag == 'poi-image-gemiler-poi-10',
      );

      // Прокручиваем до внемаршрутной плитки — она строится лениво.
      await scrollLazyUntilVisible(
        tester,
        find.text('Причал острова Гемилер'),
      );

      expect(find.text('Причал острова Гемилер'), findsOneWidget);

      final scrollable = find.byType(Scrollable).first;

      final state = tester.state<ScrollableState>(scrollable);

      // Плитка построена — тег на месте.
      expect(orphanHero, findsOneWidget);

      final scrolledTo = state.position.pixels;

      expect(scrolledTo, greaterThan(0));

      // Возврат наверх — плитка уходит из вьюпорта (ленивый список
      // её разбирает).
      await state.position.moveTo(0);

      await tester.pumpAndSettle();

      expect(orphanHero, findsNothing);

      // Второй спуск — плитка строится ЗАНОВО, тег обязан быть тем же
      // (раньше набором heroSeen.add возвращал false → null).
      await state.position.moveTo(scrolledTo);

      await tester.pumpAndSettle();

      expect(find.text('Причал острова Гемилер'), findsOneWidget);

      expect(
        orphanHero,
        findsOneWidget,
        reason: 'повторное построение ленивой плитки не теряет '
            'hero-тег',
      );
    },
  );
}
