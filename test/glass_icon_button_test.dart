// GlassIconButton (B1, 9-й проход): единая круглая «стеклянная»
// кнопка — 44 обычная / 52 primary, loading глушит тапы, active
// меняет фон, tooltip всегда есть.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:island_guide/core/widgets/glass_icon_button.dart';

void main() {
  testWidgets('обычная кнопка — 44×44 с tooltip', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GlassIconButton(
            tooltip: 'Дерево навигации',
            icon: Icons.list,
            onTap: () {},
          ),
        ),
      ),
    );

    expect(tester.getSize(find.byType(GlassIconButton)), const Size(44, 44));
    expect(find.byTooltip('Дерево навигации'), findsOne);
  });

  testWidgets('isPrimary — 52×52', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GlassIconButton(
            tooltip: 'Домой',
            icon: Icons.home,
            onTap: () {},
            isPrimary: true,
          ),
        ),
      ),
    );

    expect(tester.getSize(find.byType(GlassIconButton)), const Size(52, 52));
  });

  testWidgets('loading глушит тапы и прячет иконку', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GlassIconButton(
            tooltip: 'Определить',
            icon: Icons.my_location,
            onTap: () => taps++,
            loading: true,
          ),
        ),
      ),
    );

    expect(find.byIcon(Icons.my_location), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsOne);
    // A5 (17-й проход): спиннер НЕ глушит onTap — повторный тап
    // отменяет поиск GPS, решает сам onTap.
    await tester.tap(find.byType(GlassIconButton));
    expect(taps, 1);
  });

  testWidgets('onTap: null — тап ничего не делает', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: GlassIconButton(
            tooltip: 'Легенда',
            icon: Icons.layers,
            onTap: null,
          ),
        ),
      ),
    );

    final ink = tester.widget<InkWell>(
      find.descendant(
        of: find.byType(GlassIconButton),
        matching: find.byType(InkWell),
      ),
    );
    expect(ink.onTap, isNull);
  });

  testWidgets('active — заливка глубины', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GlassIconButton(
            tooltip: 'Следую за мной',
            icon: Icons.navigation,
            onTap: () {},
            active: true,
          ),
        ),
      ),
    );

    // активное состояние не роняет кнопку и сохраняет тап-цель
    expect(tester.getSize(find.byType(GlassIconButton)), const Size(44, 44));
    expect(tester.takeException(), isNull);
  });

  testWidgets('child заменяет иконку (звезда избранного)', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GlassIconButton(
            tooltip: 'В избранное',
            onTap: () {},
            child: const Icon(Icons.star),
          ),
        ),
      ),
    );

    expect(find.byIcon(Icons.star), findsOne);
  });
}
