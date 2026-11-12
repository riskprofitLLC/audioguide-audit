// A3 (18-й проход): старт карты с уже выданным разрешением НЕ
// должен перезапускать автогид.
//
// Раньше _startTracking при granted звал _handlePermissionGranted →
// ref.invalidate(poiEntryProvider) — провайдер пересоздавал
// PoiProximityWatcher с пустым `_inside`, и replay позиции давал
// повторное событие входа (автогид перезапускал трек). Инвалидация
// нужна только при переходе «не было прав → стало» (кнопка/плашка).
//
// Наблюдаемая метрика: запуск тела провайдера = один вызов
// gateway.checkPermission (внутри тела). При старте с granted их
// ровно ДВА: один из тела провайдера, один из _startTracking —
// и НЕТ третьего от invalidate.
//
// Контентный тест — ОДИН на файл (rootBundle под FakeAsync).

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import 'package:island_guide/features/audio/providers/auto_audio_provider.dart';
import 'package:island_guide/features/content/providers/content_providers.dart';
import 'package:island_guide/features/gps/providers/location_providers.dart';
import 'package:island_guide/features/gps/services/location_gateway.dart';
import 'package:island_guide/features/gps/services/location_service.dart';
import 'package:island_guide/features/map/presentation/widgets/map_widget.dart';
import 'package:island_guide/features/map/providers/map_provider.dart';

import 'fakes/fake_location_gateway.dart';
import 'support/test_database.dart';

void main() {
  initTestDatabase();

  testWidgets(
    'старт с granted: автогид запускается один раз (A3)',
    (WidgetTester tester) async {
      final gateway = FakeLocationGateway()
        // Разрешение уже выдано — холодный старт карты.
        ..status = LocationPermissionStatus.granted;

      final container = ProviderContainer(
        overrides: [
          currentIslandIdProvider.overrideWith((_) => 'gemiler'),
          locationServiceProvider.overrideWith((ref) {
            final service = LocationService(gateway: gateway);
            ref.onDispose(service.dispose);
            return service;
          }),
          regionMapStyleFamily('fethiye').overrideWith(
            (ref) async => '{"version":8,"sources":{},"layers":[]}',
          ),
        ],
      );

      addTearDown(container.dispose);

      // Прогрев ДО подписки автогида: poiEntryProvider стартует
      // сразу при listen и читает манифесты — из прогретого кеша,
      // а не через rootBundle из фейк-зоны (гонка зон: future,
      // созданный во фейк-зоне, не завершается никогда).
      await tester.runAsync(() async {
        await container.read(regionsProvider.future);
        await container.read(islandsProvider.future);
        await container.read(trailsFamily('gemiler').future);
        await container.read(poisFamily('gemiler').future);
      });

      // Держим автогид живым (как это делает MapPage).
      container.listen(poiEntryProvider, (_, _) {});

      rootBundle.clear();

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: Scaffold(
              body: MapWidget(
                islandId: 'gemiler',
                initialCameraPosition: CameraPosition(
                  target: LatLng(36.5548, 29.0658),
                  zoom: 12,
                ),
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Карта построилась, _startTracking отработал при granted.
      // Запусков ТЕЛА провайдера — ровно один (его собственный
      // checkPermission); invalidate из _startTracking больше нет.
      expect(
        gateway.checkPermissionCalls,
        2,
        reason: '1 вызов — тело poiEntryProvider, 1 — проверка '
            '_startTracking. Третьего (пересоздание тела после '
            'invalidate) быть не должно — иначе _inside вотчера '
            'обнулялся и replay позиции запускал трек заново (A3)',
      );
    },
  );
}
