// P0-3 (7-й проход): клавиатура и капсула на вкладке «Поиск».
//
// Раньше шторка поиска с автофокусом открывала клавиатуру, а
// Scaffold шелла имел resizeToAvoidBottomInset: true — клавиатура
// сжимала body вместе со Stack капсулы: пилюля всплывала НАД
// клавиатурой поверх результатов, а карта (platform view)
// пересчитывала размер. Теперь:
//   - шелл не сжимает body (resizeToAvoidBottomInset: false) —
//     карта не перерисовывается;
//   - капсула прячется (уезжает вниз), пока viewInsets.bottom > 0;
//   - шторка дерева добавляет viewInsets.bottom к нижнему
//     паддингу списка — результаты видны над клавиатурой.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:island_guide/app/app.dart';
import 'package:island_guide/app/navigation/navigation_shell.dart';
import 'package:island_guide/features/content/models/region_catalog.dart';
import 'package:island_guide/features/content/providers/content_providers.dart';

import 'support/test_database.dart';

void main() {
  initTestDatabase();

  // Одиночные прокачки: у поля поиска в фокусе мигает курсор —
  // pumpAndSettle не завершается (паттерн tree_navigation_test).
  Future<void> pumpFrames(WidgetTester tester, int times) async {
    for (var i = 0; i < times; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets(
    'клавиатура прячет капсулу и не сжимает контент шелла',
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

      // Капсула на месте — внизу экрана.
      final capsuleBefore = tester.getRect(find.byType(NavigationBar));

      expect(
        capsuleBefore.bottom,
        closeTo(800 - NavigationShell.capsuleBottomGap, 1),
        reason: 'до клавиатуры капсула стоит у нижней кромки',
      );

      // Тап по «Поиск»: /map?search=1, шторка с автофокусом.
      await tester.tap(find.text('Поиск'));
      await pumpFrames(tester, 6);

      expect(find.byTooltip('Закрыть'), findsOneWidget,
          reason: 'шторка поиска открыта');

      // Клавиатура «открылась»: viewInsets.bottom = 300.
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);

      await pumpFrames(tester, 8);

      // Шторка НЕ сжалась телом шелла: 92% полного окна
      // (0.92 * 800 = 736), а не 0.92 * (800 - 300).
      final sheetRect = tester.getRect(find.byType(FractionallySizedBox));

      expect(
        sheetRect.height,
        closeTo(800 * 0.92, 2),
        reason: 'тело шелла не сжимается клавиатурой — карта (platform '
            'view) не пересчитывает размер',
      );

      // Список результатов/дерева получает нижний паддинг
      // «капсула + клавиатура»: контент виден над клавиатурой.
      final scroll = tester.widget<SingleChildScrollView>(
        find.byWidgetPredicate(
          (w) =>
              w is SingleChildScrollView &&
              w.padding is EdgeInsets &&
              (w.padding as EdgeInsets).left == 10,
        ),
      );

      expect(
        (scroll.padding as EdgeInsets).bottom,
        closeTo(NavigationShell.capsuleExtent + 12 + 300, 0.5),
        reason: 'низ списка выше клавиатуры',
      );

      // Капсула спрятана: уехала ниже нижней кромки экрана.
      final capsuleWithKeyboard = tester.getRect(find.byType(NavigationBar));

      expect(
        capsuleWithKeyboard.top,
        greaterThanOrEqualTo(800),
        reason: 'при открытой клавиатуре капсула не должна висеть '
            'над ней поверх результатов (P0-3)',
      );

      // Клавиатура закрылась — капсула вернулась к кромке.
      tester.view.viewInsets = FakeViewPadding.zero;

      await pumpFrames(tester, 10);

      final capsuleAfter = tester.getRect(find.byType(NavigationBar));

      expect(
        capsuleAfter.bottom,
        closeTo(800 - NavigationShell.capsuleBottomGap, 1),
        reason: 'после закрытия клавиатуры капсула возвращается',
      );
    },
  );
}
