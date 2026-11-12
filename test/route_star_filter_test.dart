// Тест звёздочки-фильтра избранного на главном экране.
//
// Одна звёздочка на весь остров (B3: пока маршруты есть, фильтр
// живёт только в секции «Маршруты»): при включении показывает
// только избранные достопримечательности — как внутри каждого
// маршрута, так и в секции «Вне маршрута».
//
// Отдельный файл: в flutter_test rootBundle.loadString в testWidgets
// надёжно работает только в первом content-loading тесте файла —
// второй тест с загрузкой контента в том же файле зависал в
// pumpAndSettle (см. AGENTS.md).

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:island_guide/features/content/providers/content_providers.dart';
import 'package:island_guide/features/favorites/providers/favorites_providers.dart';
import 'package:island_guide/features/home/presentation/home_page.dart';

import 'support/lazy_scroll.dart';
import 'support/test_database.dart';

void main() {

  initTestDatabase();

  testWidgets(
    'Звёздочка острова фильтрует избранное в маршрутах и вне маршрута',
    (WidgetTester tester) async {
      // Стартовая локация — Гемилер. poi.json Гемилера (~55 КБ) не
      // грузится под FakeAsync (порог ~50 КБ, см. AGENTS.md) — контент
      // сеем в runAsync и читаем из кеша провайдеров (паттерн
      // tree_navigation_test).
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

      // Будущие ассетов, созданные в зоне runAsync, под FakeAsync не
      // завершаются (колбэки .then идут в зону создания Future).
      // Чистим кеш — холодные дочитывания пойдут уже в зоне теста.
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

      // Добавляем в избранное «Вход на остров Гемилер» (poi-01, в маршруте)
      // и «Причал» (poi-11, в «Локациях»).
      await container
          .read(favoritesControllerProvider.notifier)
          .toggle('gemiler/poi-01');

      await container
          .read(favoritesControllerProvider.notifier)
          .toggle('gemiler/poi-11');

      await tester.pump();

      // До включения фильтра маршрут показывает все свои POI.
      // Списки ленивые (B15): подводим строки в кадр, затем
      // возвращаемся к заголовку секции — там звёздочка.
      await scrollLazyUntilVisible(
        tester,
        find.text('Церковь на западном склоне'),
      );

      expect(find.text('Церковь на западном склоне'), findsWidgets);

      // Включаем звёздочку-фильтр острова (B1: унифицированная
      // FavoriteStar — ищем по tooltip выключенного состояния;
      // B3: фильтр один, в секции «Маршруты»).
      await scrollLazyUntilVisible(
        tester,
        find.text('Маршруты'),
        step: -400,
      );

      final filterOff = find.byTooltip(
        'Показать только избранные',
      );

      expect(filterOff, findsOneWidget);

      await tester.ensureVisible(filterOff);
      await tester.pumpAndSettle();
      await tester.tap(filterOff);
      await tester.pumpAndSettle();

      // Внутри маршрута остался только избранный POI.
      await scrollLazyUntilVisible(
        tester,
        find.text('Вход на остров Гемилер'),
      );

      expect(find.text('Вход на остров Гемилер'), findsOneWidget);
      expect(find.text('Церковь на западном склоне'), findsNothing);

      // В секции «Вне маршрута» остался избранный «Причал».
      await scrollLazyUntilVisible(
        tester,
        find.text('Причал острова Гемилер'),
      );

      expect(find.text('Вне маршрута'), findsOneWidget);
      expect(find.text('Причал острова Гемилер'), findsOneWidget);
      expect(find.text('Древние гробницы'), findsNothing);

      // Выключаем фильтр — все достопримечательности вернулись.
      await scrollLazyUntilVisible(
        tester,
        find.text('Маршруты'),
        step: -400,
      );

      final filterOn = find.byTooltip(
        'Показать все достопримечательности локации',
      );

      await tester.ensureVisible(filterOn);
      await tester.pumpAndSettle();
      await tester.tap(filterOn);
      await tester.pumpAndSettle();

      await scrollLazyUntilVisible(
        tester,
        find.text('Церковь на западном склоне'),
      );

      expect(find.text('Церковь на западном склоне'), findsWidgets);
    },
  );
}
