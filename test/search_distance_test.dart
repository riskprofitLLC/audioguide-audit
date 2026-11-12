// A5 (11-й проход), часть 1: дистанции «~2,1 км» в результатах
// поиска берутся из ПОСЛЕДНЕЙ ИЗВЕСТНОЙ позиции LocationService
// (синхронный lastKnownPosition) — открытие поиска больше не
// будит датчик разовым currentPosition() и не проверяет
// разрешение ради подписи.
//
// Нет свежей позиции — дистанций нет, датчик не запрашивался.
//
// Контентный тест — ОДИН на файл (rootBundle под FakeAsync,
// см. AGENTS.md); пара с позицией — в search_distance_lastknown_test.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:island_guide/app/app.dart';
import 'package:island_guide/features/content/providers/content_providers.dart';
import 'package:island_guide/features/gps/providers/location_providers.dart';
import 'package:island_guide/features/gps/services/location_service.dart';
import 'package:island_guide/features/navigation/presentation/tree_navigation_button.dart';
import 'package:island_guide/features/search/providers/search_providers.dart';

import 'fakes/fake_location_gateway.dart';
import 'support/test_database.dart';

void main() {
  initTestDatabase();

  testWidgets('без позиции: дистанций нет, датчик не трогается (A5)',
      (tester) async {
    final gateway = FakeLocationGateway();
    final service = LocationService(gateway: gateway);

    addTearDown(service.dispose);

    final container = ProviderContainer(
      overrides: [
        currentIslandIdProvider.overrideWith((_) => 'gemiler'),
        locationServiceProvider.overrideWithValue(service),
      ],
    );

    addTearDown(container.dispose);

    await tester.runAsync(() async {
      await container.read(regionsProvider.future);
      await container.read(islandsProvider.future);
      await container.read(searchIndexProvider.future);
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

    final treeButton = find.byType(TreeNavigationButton);

    await tester.ensureVisible(treeButton);
    await tester.tap(treeButton);
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'маяк');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 220));
    await tester.pumpAndSettle();

    // Поиск что-то нашёл — иначе тест не про то.
    expect(
      find.byKey(const ValueKey('search-poi-gemiler-poi-09')),
      findsOneWidget,
    );

    // Дистанций нет — позиции не было.
    expect(
      find.textContaining('~'),
      findsNothing,
      reason: 'без последней известной позиции дистанции не '
          'показываются (A5)',
    );

    // Датчик не запрашивался ни разовым currentPosition, ни
    // проверкой разрешения.
    expect(
      gateway.currentPositionCalls,
      0,
      reason: 'поиск не будит GPS разовым запросом (A5)',
    );

    expect(
      gateway.checkPermissionCalls,
      0,
      reason: 'поиск не проверяет разрешение ради дистанций (A5)',
    );
  });
}
