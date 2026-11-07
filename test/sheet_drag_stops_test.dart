// 1d (12-й проход): шторки POI/маршрута на карте — лист «со
// стопами» (DraggableScrollableSheet): старт на прежних 70%,
// вверх — до 95%, резкий утяг вниз — закрывает (прежний
// «жест вниз»).
//
// Проверяется контракт режима: с переданным scrollController
// шторка БЕЗ капа 70% (размер задаёт лист), автономно — кап
// прежний (регрессия poi_info_sheet_test не тронута).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:island_guide/features/map/presentation/widgets/poi_info_sheet.dart';
import 'package:island_guide/features/poi/models/poi.dart';

import 'support/test_database.dart';

void main() {
  initTestDatabase();

  const poi = Poi(
    id: 'poi-01',
    title: 'Смотровая площадка',
    latitude: 36.55,
    longitude: 29.07,
    description: 'Описание точки.',
  );

  testWidgets('лист со стопами: 70% → вверх 95% → вниз-закрытие (1d)',
      (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;

    addTearDown(tester.view.reset);

    var sheetOpen = false;

    Future<void> openSheet(WidgetTester tester) async {
      sheetOpen = false;

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => Center(
                  child: TextButton(
                    onPressed: () async {
                      sheetOpen = true;

                      await showModalBottomSheet<void>(
                        context: context,
                        isScrollControlled: true,
                        // Те же параметры, что у шторки POI на
                        // карте (map_taps.dart, 1d).
                        builder: (sheetContext) =>
                            DraggableScrollableSheet(
                          expand: false,
                          initialChildSize: 0.7,
                          minChildSize: 0.45,
                          maxChildSize: 0.95,
                          snap: true,
                          snapSizes: const [0.7],
                          builder: (context, scrollController) =>
                              PoiInfoSheet(
                            poi: poi,
                            islandId: 'gemiler',
                            scrollController: scrollController,
                          ),
                        ),
                      );

                      sheetOpen = false;
                    },
                    child: const Text('открыть'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('открыть'));
      await tester.pumpAndSettle();
    }

    await openSheet(tester);

    double sheetHeight() =>
        tester.getRect(find.byType(PoiInfoSheet)).height;

    // Старт — прежние ~70% окна (560 px на 800-px вьюпорте).
    expect(
      sheetHeight(),
      inExclusiveRange(500, 620),
      reason: 'стартовое положение листа — 70% (1d)',
    );

    // Тянем шторку вверх (по заголовку — он есть всегда) —
    // лист раскрывается к 95%.
    await tester.drag(find.text('Смотровая площадка'), const Offset(0, -300));
    await tester.pumpAndSettle();

    expect(
      sheetHeight(),
      greaterThan(700),
      reason: 'утяг вверх раскрывает лист до 95% (1d)',
    );

    // Резкий утяг вниз закрывает шторку (инвариант «жест вниз»).
    await tester.fling(
      find.text('Смотровая площадка'),
      const Offset(0, 600),
      3000,
    );
    await tester.pumpAndSettle();

    expect(
      find.byType(PoiInfoSheet),
      findsNothing,
      reason: 'резкий утяг вниз закрывает шторку (1d)',
    );

    expect(sheetOpen, isFalse, reason: 'модальный роут закрылся');
  });
}
