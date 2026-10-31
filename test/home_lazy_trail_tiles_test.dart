// A4 (8-й проход): плитки секции «Маршруты» строятся лениво.
//
// Раньше `items` — готовый список виджетов — собирался целиком в
// build: SliverList.builder лишь возвращал уже построенные
// экземпляры, ленивым оставался layout, а не создание. Для
// Финике—Антальи (46 точек маршрута) все ContentTile создавались
// разом при каждом build главной.
//
// Теперь список — плоские записи (данные), виджеты строит
// itemBuilder по индексу. Счётчик ContentTile.debugCreatedCount
// измеряет именно СОЗДАНИЕ виджетов: при открытии — только
// вошедшие во вьюпорт, прокрутка достраивает остальные.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:island_guide/features/content/models/manifest.dart';
import 'package:island_guide/features/content/providers/content_providers.dart';
import 'package:island_guide/features/home/presentation/home_page.dart';
import 'package:island_guide/core/widgets/app_card.dart';
import 'package:island_guide/core/widgets/content_tile.dart';
import 'package:island_guide/features/poi/models/poi.dart';
import 'package:island_guide/features/trails/models/trail.dart';

import 'support/test_database.dart';

void main() {
  initTestDatabase();

  testWidgets(
    'маршрутные плитки строятся лениво по записям (A4)',
    (WidgetTester tester) async {
      const islandId = 'gemiler';

      // 60 маршрутных точек — заметно больше одного экрана.
      final pois = List<Poi>.generate(
        60,
        (i) => Poi(
          id: 'poi-${i + 1}',
          title: 'Точка ${i + 1}',
          latitude: 36.55,
          longitude: 29.06,
          trailIds: const ['trail-01'],
          number: i + 1,
        ),
      );

      final trail = const Trail(
        id: 'trail-01',
        name: 'Длинный маршрут',
        points: [],
      );

      final manifest = const Manifest(
        id: islandId,
        name: 'Гемилер',
        version: 1,
        language: 'ru',
        map: '',
        trails: 'trails.geojson',
        poi: 'poi.json',
        audio: 'audio',
        images: 'images',
      );

      final container = ProviderContainer(
        overrides: [
          currentIslandIdProvider.overrideWith((_) => islandId),
          currentRegionIdProvider.overrideWith((_) => 'fethiye'),
          islandContentProvider.overrideWith((ref) async => manifest),
          regionContentProvider.overrideWith((ref) async => manifest),
          poisProvider.overrideWith((ref) async => pois),
          trailsProvider.overrideWith((ref) async => [trail]),
        ],
      );

      addTearDown(container.dispose);

      ContentTile.debugResetCreatedCount();

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: HomePage(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Карточка маршрута построена (может быть ниже фолда —
      // skipOffstage:false считает и невидимые, но ПОСТРОЕННЫЕ).
      expect(
        find.byType(TrailCard, skipOffstage: false),
        findsOneWidget,
      );

      // СОЗДАНО плиток при первом build — только вошедшие в
      // вьюпорт + cacheExtent. Раньше (готовые виджеты в items)
      // первый build создавал все 60.
      final createdAtOpen = ContentTile.debugCreatedCount;

      expect(
        createdAtOpen,
        lessThan(60),
        reason: 'плитки маршрута создаются лениво по записям '
            '(в покое — только вьюпорт + cacheExtent, у старого '
            'кода с готовым списком виджетов здесь было бы 60)',
      );

      // Прокрутка достраивает хвост по требованию.
      final state = tester.state<ScrollableState>(
        find.byType(Scrollable).first,
      );

      // Первый шаг — середина списка: плитки создаются.
      await state.position.moveTo(state.position.maxScrollExtent / 2);

      await tester.pumpAndSettle();

      expect(
        ContentTile.debugCreatedCount,
        greaterThan(createdAtOpen),
        reason: 'прокрутка достраивает новые плитки',
      );

      await state.position.moveTo(state.position.maxScrollExtent);

      await tester.pumpAndSettle();

      expect(
        ContentTile.debugCreatedCount,
        greaterThan(createdAtOpen),
        reason: 'прокрутка достраивает новые плитки',
      );

      expect(
        find.text('Точка 60', skipOffstage: false),
        findsOneWidget,
        reason: 'хвост списка достижим прокруткой',
      );
    },
  );
}
