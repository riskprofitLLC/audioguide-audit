// Тесты главного экрана: маршруты с группами достопримечательностей.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:island_guide/features/content/providers/content_providers.dart';
import 'package:island_guide/features/home/presentation/home_page.dart';
import 'package:island_guide/features/map/presentation/widgets/map_preview.dart';

import 'support/lazy_scroll.dart';
import 'support/test_database.dart';

void main() {

  initTestDatabase();

  testWidgets(
    'Главный экран показывает остров и маршруты с достопримечательностями',
    (WidgetTester tester) async {
      // Стартовая локация (флагман с маршрутом) — Гемилер.
      //
      // poi.json Гемилера (~55 КБ) не грузится через rootBundle под
      // FakeAsync (порог ~50 КБ, см. AGENTS.md), поэтому контент
      // сеется и читается здесь в реальной асинхронности runAsync —
      // значения кэшируются в провайдерах, и под FakeAsync виджет
      // читает их без загрузки (паттерн tree_navigation_test).
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
      // завершаются: колбэки .then планируются в зону СОЗДАНИЯ Future
      // (dart:async, _Future._addListener), то есть в реальный цикл,
      // заблокированный на время FakeAsync-теста. Чистим кеш rootBundle —
      // всё, что дочитается в теле теста, стартует заново уже в зоне
      // FakeAsync, а мелкие файлы (манифесты, тексты) грузятся и так.
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

      // AppBar'ы из приложения убраны — заголовок острова на главной.
      expect(find.text('Island Guide'), findsNothing);
      expect(find.text('Гемилер'), findsWidgets);

      // Вместо кнопки — мини-превью карты острова.
      expect(find.byType(MapPreview), findsOneWidget);

      // Маршруты — основная структура, отдельного списка POI нет.
      expect(find.text('Маршруты'), findsOneWidget);
      expect(find.text('Достопримечательности'), findsNothing);

      // Списки ленивые (B15): карточка маршрута строится при
      // подведении в кадр — прокручиваем к ней.
      await scrollLazyUntilVisible(
        tester,
        find.text('Маршрут по острову Гемилер'),
      );

      // На Гемилере один маршрут через пронумерованные POI.
      expect(find.text('Маршрут по острову Гемилер'), findsOneWidget);

      // «Вход на остров Гемилер» входит в единственный маршрут (trail-01).
      await scrollLazyUntilVisible(
        tester,
        find.text('Вход на остров Гемилер'),
      );

      expect(find.text('Вход на остров Гемилер'), findsOneWidget);

      // «Погост» — №4 маршрута (бывшие «Древние гробницы», вне маршрута),
      // поэтому показывается в группе маршрута, а не в секции мест.
      await scrollLazyUntilVisible(
        tester,
        find.text('Погост'),
      );

      expect(find.text('Погост'), findsOneWidget);

      // «Причал» без номера — отдельная достопримечательность в
      // секции «Вне маршрута», поэтому показывается в конце списка.
      // Основной скролл — внешний ListView (первый Scrollable),
      // ленты регионов/локаций игнорируем.
      await scrollLazyUntilVisible(
        tester,
        find.text('Причал острова Гемилер'),
      );

      // Секция вне-маршрутных точек (B2: бывш. «Локации»).
      expect(find.text('Вне маршрута'), findsOneWidget);
      expect(find.text('Причал острова Гемилер'), findsOneWidget);

      // B2.4: на широком экране (тест — 800 px) плитки выше —
      // описание вернулось, «Восточный мыс» надо прокрутить.
      await scrollLazyUntilVisible(
        tester,
        find.text('Восточный мыс'),
      );

      expect(find.text('Восточный мыс'), findsOneWidget);

      // Hero-тег внемаршрутных точек (P2, 7-й проход): это
      // основной контент bay/coast/Памфилии — миниатюра обязана
      // лететь в детали. Тег уникален в пределах страницы.
      final orphanHero = find.byWidgetPredicate(
        (w) => w is Hero && w.tag == 'poi-image-gemiler-poi-10',
      );

      expect(
        orphanHero,
        findsOneWidget,
        reason: 'у внемаршрутной плитки есть hero-тег: полёт '
            'миниатюры в детали работает',
      );
    },
  );
}
