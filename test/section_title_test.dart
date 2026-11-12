// SectionTitle: заголовок секции с ромбом, счётчиком и действием;
// compact/comfortable меняют типографику, showDiamond убирает ромб.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:island_guide/core/widgets/section_title.dart';

void main() {
  testWidgets('заголовок со счётчиком и действием', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SectionTitle(
            title: 'Маршруты',
            count: 3,
            action: TextButton(onPressed: () {}, child: const Text('Ещё')),
          ),
        ),
      ),
    );

    expect(find.text('Маршруты'), findsOne);
    expect(find.text('3'), findsOne);
    expect(find.text('Ещё'), findsOne);
  });

  testWidgets('без счётчика и действия — только заголовок', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: SectionTitle(title: 'Вне маршрута')),
      ),
    );

    expect(find.text('Вне маршрута'), findsOne);
    expect(tester.takeException(), isNull);
  });

  testWidgets('showDiamond: false убирает ромб', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SectionTitle(title: 'Без ромба', showDiamond: false),
        ),
      ),
    );

    // ромб — единственный Transform внутри секции
    expect(
      find.descendant(
        of: find.byType(SectionTitle),
        matching: find.byType(Transform),
      ),
      findsNothing,
    );
  });

  testWidgets('длинный заголовок режется, а не ломает ряд',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 200,
            child: SectionTitle(
              title: 'Очень длинное название секции которое не влезает',
              count: 12,
              action: TextButton(onPressed: () {}, child: const Text('→')),
            ),
          ),
        ),
      ),
    );

    final title = tester.widget<Text>(find.textContaining('Очень длинное'));
    expect(title.overflow, TextOverflow.ellipsis);
    expect(tester.takeException(), isNull);
  });

  testWidgets('AppDivider рисует линию заданной толщины', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: AppDivider(height: 2, indent: 8, endIndent: 8)),
      ),
    );

    final divider = tester.widget<Divider>(find.byType(Divider));
    expect(divider.thickness, 2);
    expect(divider.indent, 8);
    expect(divider.endIndent, 8);
  });
}
