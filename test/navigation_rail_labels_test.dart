// A5 (8-й проход): рельс навигации на планшете — подписи и подсказки.
//
// На ширине 600–800 (основной тестовый планшет ZENO 1 — 601 dp)
// рельс был labelType: none — четыре иконки без текста: «Карта»,
// «Избранное», «Поиск» неочевидны. Теперь:
//   600–800 → NavigationRailLabelType.all (подписи под иконками),
//   ≥800    → extended (подписи рядом),
//   + Tooltip на каждой destination.
// Проверяем также отсутствие overflow на textScale 1.6.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:island_guide/app/navigation/navigation_shell.dart';

void main() {
  Future<void> pumpShell(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: NavigationShell(
            selectedIndex: 0,
            child: Container(color: Colors.white),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();
  }

  testWidgets('601 dp: подписи под иконками + tooltip (A5)', (tester) async {
    tester.view.physicalSize = const Size(601, 800);
    tester.view.devicePixelRatio = 1.0;

    addTearDown(tester.view.reset);

    await pumpShell(tester);

    final rail = tester.widget<NavigationRail>(
      find.byType(NavigationRail),
    );

    expect(rail.labelType, NavigationRailLabelType.all);
    expect(rail.extended, isFalse);

    // Подписи видны под иконками.
    expect(find.text('Главная'), findsOneWidget);
    expect(find.text('Карта'), findsOneWidget);
    expect(find.text('Избранное'), findsOneWidget);
    expect(find.text('Поиск'), findsOneWidget);

    // Tooltip на каждой destination — и на обычной, и на
    // выделенной иконке.
    for (final label in ['Главная', 'Карта', 'Избранное', 'Поиск']) {
      expect(
        find.byTooltip(label),
        findsWidgets,
        reason: 'у destination «$label» есть tooltip',
      );
    }
  });

  testWidgets('800 dp: extended рельс с подписями (A5)', (tester) async {
    tester.view.physicalSize = const Size(800, 800);
    tester.view.devicePixelRatio = 1.0;

    addTearDown(tester.view.reset);

    await pumpShell(tester);

    final rail = tester.widget<NavigationRail>(
      find.byType(NavigationRail),
    );

    expect(rail.extended, isTrue);

    // Extended рисует подписи сам — тексты в дереве.
    expect(find.text('Поиск'), findsOneWidget);
  });

  testWidgets('601 dp при textScale 1.6 — без overflow (A5)', (tester) async {
    tester.view.physicalSize = const Size(601, 800);
    tester.view.devicePixelRatio = 1.0;

    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        child: MediaQuery(
          data: const MediaQueryData(
            textScaler: TextScaler.linear(1.6),
          ),
          child: MaterialApp(
            home: NavigationShell(
              selectedIndex: 0,
              child: Container(color: Colors.white),
            ),
          ),
        ),
      ),
    );

    // Увеличенные подписи не переполняют рельс: никаких
    // исключений переполнения за pumpAndSettle.
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);

    expect(find.text('Избранное'), findsOneWidget);
  });
}
