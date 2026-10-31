// Системный «Назад» на вкладках (P0-11, 6-й проход): back с
// карты/избранного возвращает на главную, а не закрывает
// приложение (единственный роут ветки «пузырил» back до
// SystemNavigator.pop). Повторный back уже с главной — выход.
// Модальная шторка ветки закрывается бэком раньше перехода.

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

  Future<void> pumpFrames(WidgetTester tester, int times) async {
    for (var i = 0; i < times; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets('back с вкладок: на главную, шторка закрывается раньше',
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

    await tester.pump(const Duration(milliseconds: 1200));
    await pumpFrames(tester, 3);

    final router = AppRouter.router;

    String location() =>
        router.routerDelegate.currentConfiguration.uri.toString();

    expect(location(), '/home');

    // Уходим на карту и открываем шторку поиска.
    router.go('/map?search=1');
    await pumpFrames(tester, 4);

    expect(find.byTooltip('Закрыть'), findsOneWidget,
        reason: 'шторка поиска открыта');

    // Back #1: сначала закрывается ШТОРКА (её роут выше роута
    // ветки), приложение остаётся на карте.
    await tester.binding.handlePopRoute();

    await pumpFrames(tester, 6);

    expect(find.byTooltip('Закрыть'), findsNothing,
        reason: 'back закрыл шторку, а не приложение');

    expect(router.routerDelegate.currentConfiguration.uri.path, '/map',
        reason: 'после закрытия шторки остаёмся на карте');

    // Back #2: с карты — возврат на главную (раньше приложение
    // закрывалось: единственный роут ветки пузырил back).
    await tester.binding.handlePopRoute();

    await pumpFrames(tester, 6);

    expect(location(), '/home',
        reason: 'back с карты возвращает на главную');

    // Back #3: с главной — штатный выход (canPop: true, состояние
    // роута не перехватывается).
    final handled = await tester.binding.handlePopRoute();

    expect(handled, isFalse,
        reason: 'с главной back не перехватывается фреймворком — '
            'системный выход');

    // Избранное: back тоже возвращает на главную.
    router.go('/favorites');
    await pumpFrames(tester, 4);

    await tester.binding.handlePopRoute();

    await pumpFrames(tester, 6);

    expect(location(), '/home',
        reason: 'back из избранного возвращает на главную');
  });
}
