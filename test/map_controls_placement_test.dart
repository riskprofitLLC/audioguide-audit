// Расположение системных контролов карты (P0-3, 5-й проход):
// компас и атрибуция OSM — колонкой в правом верхнем углу СЛЕВА
// от кластера «дерево»+«легенда» (right:16). Раньше компас
// (topLeft) пересекался с чипом ближайшего POI и баннером
// запрета, а атрибуцию (bottomLeft) закрывала парящая капсула
// навигации.

import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import 'package:island_guide/features/content/providers/content_providers.dart';
import 'package:island_guide/features/map/presentation/pages/map_page.dart';
import 'package:island_guide/features/map/providers/map_provider.dart';

import 'support/test_database.dart';

void main() {

  initTestDatabase();

  testWidgets('компас и атрибуция не пересекаются с чипом и кластером',
      (tester) async {
    // Телефон 360x640: чип ближайшего POI в левом верхнем углу,
    // кластер «дерево»+легенда — в правом (right:16, top:14/70).
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1.0;

    addTearDown(tester.view.reset);

    final container = ProviderContainer(
      overrides: [
        currentIslandIdProvider.overrideWith((_) => 'gemiler'),
        // Стиль подменяем минимальной заглушкой: реальный
        // IO-стиль зовет path_provider (pmtilesUrl), канала
        // которого в тесте нет. Для проверки раскладки контролов
        // содержимое стиля не важно — важен сам MapLibreMap.
        mapStyleFamily('gemiler').overrideWith(
          (ref) async => '{"version":8,"sources":{},"layers":[]}',
        ),
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

    // Явная камера — MapLibreMap строится сразу, не дожидаясь
    // подгонки под маршруты.
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: MapPage(
            lat: 36.55,
            lng: 29.07,
            zoom: 14,
            islandId: 'gemiler',
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    final map = tester.widget<MapLibreMap>(find.byType(MapLibreMap));

    // Компас: правый верхний угол, 76 px от правой кромки —
    // левее кластера «дерево» (right:16, ширина 44).
    expect(map.compassEnabled, isTrue);
    expect(map.compassViewPosition, CompassViewPosition.topRight);
    expect(map.compassViewMargins, const Point(76, 14));

    // Атрибуция OSM — той же колонкой под компасом, видна всегда
    // (капсула навигации больше не закрывает нижний угол).
    expect(
      map.attributionButtonPosition,
      AttributionButtonPosition.topRight,
    );
    expect(map.attributionButtonMargins, const Point(76, 60));

    // --- Режим с подсветкой (?poi=): пилюля «К описанию» ---
    //
    // Воспроизведение (P0-6, 6-й проход): пилюля занимает
    // y 14..58, x от правой кромки 16..187; компас — y 14..54,
    // x 76..116 — прямоугольники пересекались. Фикс — колонка
    // контролов уходит ниже пилюли.
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: MapPage(
            lat: 36.55,
            lng: 29.07,
            zoom: 14,
            islandId: 'gemiler',
            highlightPoiId: 'poi-01',
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.byTooltip('К описанию'), findsOneWidget);

    final pillRow = tester.getRect(find.byTooltip('К описанию'));

    // Тап-цель пилюли — не ниже 44 (P1-1, 6-й проход).
    expect(
      pillRow.height,
      greaterThanOrEqualTo(44),
      reason: 'тап-цель «К описанию» не ниже 44',
    );

    final highlighted = tester.widget<MapLibreMap>(find.byType(MapLibreMap));

    // Колонка компас+атрибуция ушла ПОД пилюлю: верх компаса
    // не ниже нижней кромки пилюли.
    final compassTop = highlighted.compassViewMargins!.y.toDouble();

    expect(
      compassTop,
      greaterThanOrEqualTo(pillRow.bottom),
      reason: 'компас больше не пересекает пилюлю «К описанию»',
    );

    expect(highlighted.compassViewMargins, const Point(76, 66));

    // Атрибуция — той же колонкой, под компасом.
    expect(
      highlighted.attributionButtonMargins!.y.toDouble(),
      greaterThan(compassTop),
    );

    // Баннер запрета (top:64) тоже не заходит под расширенный
    // кластер: нижняя кромка пилюли обязана быть выше его верха.
    expect(
      pillRow.bottom,
      lessThanOrEqualTo(64),
      reason: 'баннер запрета (top:64) не должен пересекаться с '
          'правым верхним кластером',
    );
  });
}
