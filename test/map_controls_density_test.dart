// Плотность Android: поля компаса/атрибуции maplibre задаются
// в ПИКСЕЛЯХ — dp-значения масштабируются на devicePixelRatio,
// иначе на телефоне компас уезжал под пилюлю «К описанию».
//
// Контентный тест — ОДИН на файл (rootBundle под FakeAsync).

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import 'package:island_guide/features/content/providers/content_providers.dart';
import 'package:island_guide/features/map/presentation/pages/map_page.dart';
import 'package:island_guide/features/map/providers/map_provider.dart';

import 'support/test_database.dart';

void main() {
  initTestDatabase();

  testWidgets('на плотном Android поля компаса × dpr (кроме web/iOS)',
      (tester) async {
    tester.view
      ..physicalSize = const Size(1080, 2400) // 360x800 @3x
      ..devicePixelRatio = 3.0;

    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final container = ProviderContainer(
      overrides: [
        currentIslandIdProvider.overrideWith((_) => 'gemiler'),
        regionMapStyleFamily('fethiye').overrideWith(
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

    final map = tester.widget<MapLibreMap>(find.byType(MapLibreMap));

    // Плотность 3: dp переводится в пиксели — компас правее
    // кластера кнопок (76 dp) и ниже пилюли (14 + 52 dp).
    expect(map.compassViewMargins, const Point(228.0, 198.0));
    expect(map.attributionButtonMargins, const Point(228.0, 336.0));
  });
}
