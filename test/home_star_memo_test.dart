// A7 (10-й проход): тап по звезде на главной не пересчитывает
// тяжёлую группировку (сортировка POI + разбивка по маршрутам).
//
// Раньше любой чих избранного перестраивал весь build и пересчитывал
// sortedPois/poisByTrail/trailsWithPois. Теперь группировка
// мемоизована по идентичности списков — счётчик пересчётов
// (HomePage.debugModelComputations) не растёт от тапа по звезде.

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:island_guide/app/app.dart';
import 'package:island_guide/features/content/providers/content_providers.dart';
import 'package:island_guide/features/favorites/providers/favorites_providers.dart';
import 'package:island_guide/core/widgets/content_tile.dart';
import 'package:island_guide/features/home/presentation/home_page.dart';

import 'support/lazy_scroll.dart';
import 'support/test_database.dart';

void main() {
  initTestDatabase();

  testWidgets('тап по звезде не пересчитывает группировку (A7)',
      (tester) async {
    HomePage.debugModelComputations = 0;

    final container = ProviderContainer(
      overrides: [
        currentIslandIdProvider.overrideWith((_) => 'gemiler'),
      ],
    );

    addTearDown(container.dispose);

    await tester.runAsync(() async {
      await container.read(regionsProvider.future);
      await container.read(islandsProvider.future);
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

    await tester.pumpAndSettle();
    await tester.pumpAndSettle();

    // Главная собрана — группировка посчитана минимум один раз
    // (первый build мог гнать перестройки до прихода данных).
    final afterFirstLayout = HomePage.debugModelComputations;

    expect(afterFirstLayout, greaterThanOrEqualTo(1));

    // Постукиваем пару кадров без изменений — без данных модель
    // не пересчитывается.
    await tester.pumpAndSettle();

    expect(HomePage.debugModelComputations, afterFirstLayout);

    // Тап по звезде первого POI маршрута: избранное меняется,
    // списки POI/маршрутов — НЕТ, группировка обязана взяться из
    // мемо-кеша. Главная ленивая — звезду подводим прокруткой
    // (паттерн scrollLazyUntilVisible).
    final emptyStars = find.descendant(
      of: find.byType(ContentTile),
      matching: find.byTooltip('В избранное'),
    );

    await scrollLazyUntilVisible(tester, emptyStars);

    final star = emptyStars.first;

    await tester.ensureVisible(star);
    await tester.pumpAndSettle();

    await tester.tap(star);
    await tester.pumpAndSettle();

    expect(
      HomePage.debugModelComputations,
      afterFirstLayout,
      reason: 'звезда меняет только избранное — группировка '
          'переиспользуется из мемо-кеша (A7)',
    );

    // Состояние действительно изменилось: звезда «заполнена».
    expect(find.byTooltip('Убрать из избранного'), findsWidgets);

    // Второй тап — снятие избранного, тоже без пересчёта.
    final filledStars = find.descendant(
      of: find.byType(ContentTile),
      matching: find.byTooltip('Убрать из избранного'),
    );

    await scrollLazyUntilVisible(tester, filledStars);

    final filledStar = filledStars.first;

    await tester.ensureVisible(filledStar);
    await tester.pumpAndSettle();

    await tester.tap(filledStar);
    await tester.pumpAndSettle();

    expect(HomePage.debugModelComputations, afterFirstLayout);

    expect(container.read(favoritesControllerProvider), isEmpty);
  });
}
