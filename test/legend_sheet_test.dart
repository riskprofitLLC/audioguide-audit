// A1 (11-й проход): в шторке легенды карты строка
// «Достопримечательность» была продублирована (копипаст) —
// тест фиксирует отсутствие повторов у всех пунктов легенды.

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

  testWidgets('легенда карты: каждый пункт ровно один, дублей нет (A1)',
      (tester) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1.0;

    addTearDown(tester.view.reset);

    final container = ProviderContainer(
      overrides: [
        currentIslandIdProvider.overrideWith((_) => 'gemiler'),
        // Стиль подменяем заглушкой: реальный IO-стиль зовет
        // path_provider, которого в тесте нет.
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

    // Открываем шторку легенды кнопкой в правом верхнем кластере.
    await tester.tap(find.byTooltip('Легенда'));
    await tester.pumpAndSettle();

    // Шторка открылась.
    expect(find.text('Легенда карты'), findsOneWidget);

    // Главный регрессион: строка «Достопримечательность» —
    // ровно одна (раньше — две подряд).
    expect(
      find.text('Достопримечательность'),
      findsOneWidget,
      reason: 'дубль первой строки легенды (A1)',
    );

    // Общее правило: ни один пункт легенды не повторяется.
    // Собираем все Text-подписи ВНУТРИ шторки (за ней на карте
    // остались чипы фильтра категорий — их подписи легитимно
    // совпадают с чипами легенды, это разные контролы).
    final legendTexts = tester
        .widgetList<Text>(
          find.descendant(
            of: find.byType(BottomSheet),
            matching: find.byWidgetPredicate((widget) {
            if (widget is! Text) return false;
            final data = widget.data;
            if (data == null) return false;
            // Подписи пунктов легенды и чипов категорий; служебные
            // строки шапки/атрибуции исключаем.
            return data != 'Легенда карты' &&
                data != 'Категории точек:' &&
                !data.startsWith('©');
            }),
          ),
        )
        .map((text) => text.data!)
        .toList();

    expect(legendTexts, isNotEmpty,
        reason: 'в шторке должны быть пункты легенды');

    final duplicates = legendTexts
        .where((label) => legendTexts.where((l) => l == label).length > 1)
        .toSet();

    expect(
      duplicates,
      isEmpty,
      reason: 'пункты легенды не должны повторяться, дубли: $duplicates',
    );

    // Ключевые строки на месте (после удаления дубля ничего
    // не потерялось).
    expect(find.text('Маршрут'), findsOneWidget);

    // D6: маркер «Вы здесь» — тремя состояниями-образцами.
    expect(find.textContaining('Вы здесь — свежий фикс'),
        findsOneWidget);
    expect(find.textContaining('Фикс устарел'),
        findsOneWidget);
    expect(find.textContaining('Сигнал потерян'),
        findsOneWidget);
    expect(find.text('Выделенная точка (пульс)'), findsOneWidget);

    // MapLibreMap всё ещё жив под шторкой (шторка не роняет карту).
    expect(find.byType(MapLibreMap), findsOneWidget);
  });
}
