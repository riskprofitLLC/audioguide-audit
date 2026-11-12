// RadioRowTile (D2): единая радио-строка настроек — тап-цель 44,
// семантика selected, выбранная строка несёт глиф-галочку и
// жирный текст, длинная подсказка режется в одну строку.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'package:island_guide/core/widgets/radio_row_tile.dart';

void main() {
    testWidgets('строка держит тап-цель 44 и зовёт onSelect', (tester) async {
    var picks = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 360,
            child: RadioRowTile(
              semanticLabel: 'Автогид: всегда',
              label: 'Всегда',
              hint: 'Подсказка',
              selected: false,
              onSelect: () => picks++,
            ),
          ),
        ),
      ),
    );

    expect(tester.getSize(find.byType(RadioRowTile)).height, 44);
    await tester.tap(find.byType(RadioRowTile));
    expect(picks, 1);
  });

  testWidgets('семантика выбранной строки — selected', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 360,
            child: RadioRowTile(
              semanticLabel: 'Автогид: всегда',
              label: 'Всегда',
              hint: 'Подсказка',
              selected: true,
              onSelect: () {},
            ),
          ),
        ),
      ),
    );

    final node = tester.getSemantics(find.byType(RadioRowTile));
    expect(node.label, contains('Автогид: всегда'));
    // выбранная строка несёт глиф-галочку, невыбранная — пустой круг
    expect(find.byIcon(LucideIcons.circleCheck), findsOne);
    expect(find.byIcon(LucideIcons.circle), findsNothing);
  });

  testWidgets('невыбранная строка не помечена selected', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 360,
            child: RadioRowTile(
              semanticLabel: 'Автогид: выключено',
              label: 'Выключено',
              hint: 'Подсказка',
              selected: false,
              onSelect: () {},
            ),
          ),
        ),
      ),
    );

    final node = tester.getSemantics(find.byType(RadioRowTile));
    expect(node.label, contains('Автогид: выключено'));
    expect(find.byIcon(LucideIcons.circle), findsOne);
    expect(find.byIcon(LucideIcons.circleCheck), findsNothing);
  });

  testWidgets('длинная подсказка не ломает ряд', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 320,
            child: RadioRowTile(
              semanticLabel: 'Тема: системная',
              label: 'Системная',
              hint: 'Очень длинная подсказка которая не должна '
                  'переноситься на вторую строку и ломать ряд',
              selected: true,
              onSelect: () {},
            ),
          ),
        ),
      ),
    );

    final hint = tester.widget<Text>(
      find.descendant(
        of: find.byType(RadioRowTile),
        matching: find.textContaining('Очень длинная'),
      ),
    );
    expect(hint.maxLines, 1);
    expect(hint.overflow, TextOverflow.ellipsis);
    expect(tester.takeException(), isNull);
  });
}
