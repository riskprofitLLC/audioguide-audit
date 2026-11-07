// Hero-теги в IndexedStack веток шелла (P1-4, 6-й проход):
// главная и избранное строят ContentTile с ОДИНАКОВЫМ тегом
// poi-image-<island>-<poi>, обе страницы живут в стеке веток
// одновременно — push деталей POI давал «multiple heroes share
// the same tag».

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:island_guide/app/app.dart';
import 'package:island_guide/app/router.dart';
import 'package:island_guide/features/content/models/region_catalog.dart';
import 'package:island_guide/features/content/providers/content_providers.dart';
import 'package:island_guide/features/favorites/providers/favorites_providers.dart';

import 'support/test_database.dart';

void main() {
  initTestDatabase();

  testWidgets('push деталей не падает от дублей Hero-тегов веток',
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

    // Контент всех локаций — паттерн tree_navigation_test.
    await tester.runAsync(() async {
      await container.read(regionsProvider.future);
      await container.read(islandsProvider.future);

      for (final id in kLocationIds) {
        await container.read(trailsFamily(id).future);
        await container.read(poisFamily(id).future);
      }

      // POI в избранном: плитка появится и на главной, и в
      // избранном — с одним и тем же hero-тегом.
      await container
          .read(favoritesControllerProvider.notifier)
          .toggle('gemiler/poi-01');
    });

    rootBundle.clear();

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const IslandGuideApp(),
      ),
    );

    await tester.pump(const Duration(milliseconds: 1200));

    // Обе ветки построены: главная (активная) и избранное.
    AppRouter.router.go('/favorites');

    await tester.pumpAndSettle();

    AppRouter.router.go('/home');

    await tester.pumpAndSettle();

    // Push деталей POI: раньше здесь летело «multiple heroes
    // share the same tag» — обе ветки в стеке строят плитки
    // poi-01 с тегом poi-image-gemiler-poi-01.
    // push возвращает Future, завершающийся при pop, — намеренно не ждём.
    unawaited(AppRouter.router.push('/poi/poi-01?island=gemiler'));

    await tester.pump();
    await tester.pumpAndSettle();

    expect(
      tester.takeException(),
      isNull,
      reason: 'push деталей при построенных ветках главной и '
          'избранного не должен падать дублями Hero-тегов',
    );

    // Детали открылись: пилюля «назад» (в hero- и полной шапке).
    expect(
      find.byTooltip('Назад'),
      findsNWidgets(2),
      reason: 'страница деталей POI построена поверх веток шелла',
    );
  });
}
