// Тесты переключения регионов и локаций на главном экране.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:island_guide/features/content/providers/content_providers.dart';
import 'package:island_guide/features/home/presentation/home_page.dart';

import 'support/test_database.dart';

void main() {

  initTestDatabase();

  testWidgets(
    'Ленты регионов и локаций меняют контент',
    (WidgetTester tester) async {
      // Стартуем с Гемилера: poi.json Гемилера (~55 КБ) не грузится
      // под FakeAsync (порог ~50 КБ, см. AGENTS.md), поэтому контент
      // стартовой локации сеем в runAsync и читаем из кеша
      // провайдеров (паттерн tree_navigation_test).
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
      // Чистим кеш — холодные дочитывания (манифесты Ликии и её
      // локаций после переключения региона) пойдут уже в зоне теста.
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

      // Начальный регион — первый в каталоге (fethiye),
      // локация — Гемилер.
      expect(
        find.text('Залив Фетхие'),
        findsWidgets,
      );

      // Лента регионов: все регионы, Ликия — чипом.
      expect(
        find.text('Ликия'),
        findsWidgets,
      );

      // Лента локаций региона: текущая (gemiler) подсвечена,
      // остальные названы. В регионе Фетхие две локации:
      // «Фетхие и Гёчек» (bay) и «Гемилер»; отдельной локации
      // «Караджаорен» больше нет — остров стал точкой в bay.
      expect(
        find.text('Гемилер'),
        findsWidgets,
      );
      expect(
        find.text('Фетхие и Гёчек'),
        findsWidgets,
      );
      expect(
        find.text('Караджаорен'),
        findsNothing,
      );

      // Переключаемся на регион Ликия: стартовая
      // локация — первая в регионе (coast). coast/poi.json ~120KB,
      // под FakeAsync через rootBundle виснет — грузим в runAsync.
      await tester.ensureVisible(
        find.text('Ликия').first,
      );

      await tester.tap(
        find.text('Ликия').first,
      );

      await tester.runAsync(() async {
        // ждём загрузки poi.json coast (путь к провайдеру лежит через
        // poisFamily — реальный асинхронный rootBundle-IO).
        final pois = await container
            .read(poisFamily('coast').future)
            .timeout(const Duration(seconds: 30));
        expect(pois, isNotEmpty);

        // Ждём появления пилюль локаций (манифесты coast + kekova).
        var pills = false;
        for (var i = 0; i < 100 && !pills; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 50));
          await tester.pump();
          pills = tester.any(
            find.text('Остров Кекова', skipOffstage: false),
          );
        }
        expect(pills, isTrue, reason: 'пилюля Остров Кекова не появилась');
      });

      expect(
        container.read(currentRegionIdProvider),
        'lykia',
      );
      expect(
        container.read(currentIslandIdProvider),
        'coast',
      );

      // У побережья пешие маршруты разрешены — баннера нет.
      expect(
        find.text('Пешие маршруты запрещены'),
        findsNothing,
      );

      // Переключаемся на локацию Остров Кекова.
      await tester.ensureVisible(
        find.text('Остров Кекова'),
      );

      await tester.tap(
        find.text('Остров Кекова'),
      );

      await tester.runAsync(() async {
        // Пакет kekova грузится реальным ІО — ждём его в runAsync.
        final pois = await container
            .read(poisFamily('kekova').future)
            .timeout(const Duration(seconds: 30));
        final trails = await container
            .read(trailsFamily('kekova').future)
            .timeout(const Duration(seconds: 30));
        expect(pois, isNotEmpty);
        expect(trails, isEmpty);
        // Даём баннеру и списку появиться.
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
      });

      expect(
        container.read(currentIslandIdProvider),
        'kekova',
      );

      // Для Кекова пешие маршруты запрещены — показывается пометка,
      // гемилерских точек нет, точки Кекова есть.
      expect(
        find.text('Пешие маршруты запрещены'),
        findsWidgets,
      );
      expect(
        find.text('Пока нет маршрутов'),
        findsNothing,
      );
      expect(
        find.text('Бухта Терсане и базилика', skipOffstage: false),
        findsWidgets,
      );
    },
  );
}