// Роутер (P0-7, 5-й проход): вкладки живут в IndexedStack —
// состояние ветвей НЕ сбрасывается при переключении; битый URL
// уходит redirect'ом на /home; /search — это /map?search=1
// (живая карта с шторкой поиска, второй MapPage не строится).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:island_guide/app/app.dart';
import 'package:island_guide/app/router.dart';
import 'package:island_guide/features/content/providers/content_providers.dart';

import 'support/test_database.dart';

void main() {

  initTestDatabase();

  testWidgets('вкладки не сбрасывают состояние, битый URL → /home',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentIslandIdProvider.overrideWith((_) => 'gemiler'),
        ],
        child: const IslandGuideApp(),
      ),
    );

    // Сплэш 900 мс → /home.
    await tester.pump(const Duration(milliseconds: 1200));
    await tester.pump(const Duration(milliseconds: 100));

    final router = AppRouter.router;

    expect(
      router.routerDelegate.currentConfiguration.uri.path,
      '/home',
    );

    // Прокручиваем главную и запоминаем позицию.
    final homeFinder = find.byType(Scrollable).first;

    await tester.drag(homeFinder, const Offset(0, -260));
    await tester.pump();

    final pixelsBefore = tester
        .state<ScrollableState>(homeFinder)
        .position
        .pixels;

    expect(pixelsBefore, greaterThan(0), reason: 'главная прокручена');

    // Уходим на карту и возвращаемся: IndexedStack обязан
    // сохранить и позицию скролла, и саму ветвь живой — раньше
    // ShellRoute пересоздавал страницу, позиция сбрасывалась.
    router.go('/map');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      router.routerDelegate.currentConfiguration.uri.path,
      '/map',
    );

    router.go('/home');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      tester.state<ScrollableState>(homeFinder).position.pixels,
      pixelsBefore,
      reason: 'позиция скролла главной пережила переключение вкладок',
    );

    // Битый URL уходит redirect'ом на /home (не errorBuilder'ом
    // с подменой страницы под «битым» адресом).
    router.go('/no-such-page');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      router.routerDelegate.currentConfiguration.uri.path,
      '/home',
      reason: 'несуществующий адрес редиректится на /home',
    );

    // /search — НЕ отдельная страница: это /map?search=1, и
    // подсвечена вкладка «Поиск».
    router.go('/search');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final uri = router.routerDelegate.currentConfiguration.uri;

    expect(uri.path, '/map');
    expect(uri.queryParameters['search'], '1');

    final rail = tester.widget<NavigationRail>(
      find.byType(NavigationRail),
    );

    expect(rail.selectedIndex, 3,
        reason: 'на /map?search=1 подсвечена вкладка «Поиск»');
  });
}
