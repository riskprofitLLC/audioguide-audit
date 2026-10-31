// B3 (17-й проход): единая плашка статуса геолокации —
// чисто виджетные проверки (без карты и контента): подписи
// вариантов, тап-цель ≥44, семантика, тап.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:island_guide/features/map/presentation/widgets/map_location_status_pill.dart';

void main() {
  Future<void> pumpPill(
    WidgetTester tester,
    MapLocationStatus status,
    List<String> taps,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: MapLocationStatusPill(
              status: status,
              onTap: () => taps.add('tap'),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('вариант «нет разрешения» — подпись и тап-цель 44',
      (tester) async {
    final taps = <String>[];

    await pumpPill(tester, MapLocationStatus.noPermission, taps);

    expect(find.text('Включить геолокацию'), findsOneWidget);

    final rect = tester.getRect(find.byType(MapLocationStatusPill));

    expect(rect.height, greaterThanOrEqualTo(44));
    expect(rect.width, greaterThanOrEqualTo(44));

    await tester.tap(find.byType(MapLocationStatusPill));

    expect(taps, ['tap']);
  });

  testWidgets('служебные варианты: выключенная служба и «навсегда»',
      (tester) async {
    await pumpPill(tester, MapLocationStatus.serviceOff, []);

    expect(find.text('Включить службу'), findsOneWidget);

    await pumpPill(tester, MapLocationStatus.deniedForever, []);

    expect(find.text('Открыть настройки'), findsOneWidget);
  });

  testWidgets('приблизительная точность — подсказка про точную геолокацию',
      (tester) async {
    await pumpPill(tester, MapLocationStatus.reducedAccuracy, []);

    expect(find.text('Точная геолокация выключена'), findsOneWidget);
  });

  testWidgets('поиск сигнала — подпись и семантика', (tester) async {
    final semantics = tester.ensureSemantics();

    await pumpPill(tester, MapLocationStatus.searchingSignal, []);

    expect(find.text('Ищем сигнал GPS…'), findsOneWidget);

    // Семантика для скринридера (B5) — полный текст статуса.
    expect(
      find.bySemanticsLabel(RegExp('Ищем сигнал GPS\\. Нажмите, чтобы '
          'определить позицию ещё раз')),
      findsOneWidget,
    );

    semantics.dispose();
  });

  testWidgets('семантика варианта «нет разрешения»', (tester) async {
    final semantics = tester.ensureSemantics();

    await pumpPill(tester, MapLocationStatus.noPermission, []);

    expect(
      find.bySemanticsLabel(RegExp('Геолокация выключена\\. Нажмите, '
          'чтобы разрешить доступ')),
      findsOneWidget,
    );

    semantics.dispose();
  });

  testWidgets('узкий экран 360 + textScale 1.6: длинная подпись не переполняет',
      (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1.0;

    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(1.6)),
          child: child!,
        ),
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: MapLocationStatusPill(
              status: MapLocationStatus.reducedAccuracy,
              onTap: () {},
            ),
          ),
        ),
      ),
    );

    // Переполнение роняет тест само (гибкое переполнение красной
    // плашкой в debug), но фиксируем и границу явно.
    expect(tester.takeException(), isNull);

    final rect = tester.getRect(find.byType(MapLocationStatusPill));

    expect(rect.right, lessThanOrEqualTo(360));
  });
}
