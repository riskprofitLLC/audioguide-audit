// A5 (11-й проход), часть 2: в результатах поиска показываются
// дистанции из ПОСЛЕДНЕЙ ИЗВЕСТНОЙ позиции (lastKnownPosition),
// при этом датчик НЕ запрашивается — подпись «~2 км» не должна
// стоить разового GPS-запроса на 15 секунд.
//
// Контентный тест — ОДИН на файл (rootBundle под FakeAsync,
// см. AGENTS.md); пара без позиции — в search_distance_test.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:island_guide/app/app.dart';
import 'package:island_guide/features/content/providers/content_providers.dart';
import 'package:island_guide/features/gps/models/user_position.dart';
import 'package:island_guide/features/gps/providers/location_providers.dart';
import 'package:island_guide/features/gps/services/location_service.dart';
import 'package:island_guide/features/navigation/presentation/tree_navigation_button.dart';
import 'package:island_guide/features/search/providers/search_providers.dart';

import 'fakes/fake_location_gateway.dart';
import 'support/test_database.dart';

void main() {
  initTestDatabase();

  testWidgets('со свежей позицией: дистанции показаны, без запроса датчика (A5)',
      (tester) async {
    final gateway = FakeLocationGateway();
    final service = LocationService(gateway: gateway);

    addTearDown(service.dispose);

    // «Живой» GPS уже работал: сервис держит подписку на поток
    // позиций (как карта). Синхронный cancel Stream.multi под
    // FakeAsync висит — подписку закрывает dispose сервиса
    // в teardown (onDone), ручной cancel не нужен.
    // ignore: cancel_subscriptions
    service.positions.listen((_) {});

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

    // Фикс GPS «только что» — у маяка Гемилера (poi-09): для
    // сортировки «Рядом» (1a) ближайшее совпадение — именно он.
    gateway.emit(
      UserPosition(
        latitude: 36.552928,
        longitude: 29.067847,
        timestamp: DateTime.now(),
      ),
    );

    await tester.pumpAndSettle();

    final treeButton = find.byType(TreeNavigationButton);

    await tester.ensureVisible(treeButton);
    await tester.tap(treeButton);
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'маяк');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 220));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('search-poi-gemiler-poi-09')),
      findsOneWidget,
    );

    // Дистанции показаны — из lastKnownPosition, без датчика.
    expect(
      find.textContaining('~'),
      findsWidgets,
      reason: 'свежая lastKnownPosition даёт подписи дистанций (A5)',
    );

    expect(
      gateway.currentPositionCalls,
      0,
      reason: 'дистанции берутся из буфера, датчик не запрашивается (A5)',
    );

    // «Рядом» (1a 12-го прохода): позиция — у самого маяка
    // Гемилера (poi-09) → совпадения по «маяк» отсортированы по
    // дистанции, маяк Гемилера — первая строка мест.
    final poiRows = find.byWidgetPredicate(
      (w) => w.key is ValueKey<String> && (w.key as ValueKey<String>).value.startsWith('search-poi-'),
    );

    final firstRowKey = (tester.widgetList(poiRows).first.key as ValueKey<String>).value;

    expect(
      firstRowKey,
      'search-poi-gemiler-poi-09',
      reason: 'ближайшее к позиции совпадение — первым (1a)',
    );
  });
}
