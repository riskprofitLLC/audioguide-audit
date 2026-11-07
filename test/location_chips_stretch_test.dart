// Лента локаций главной: кнопки растягиваются на всю ширину, когда
// экран позволяет (замечание владельца: «Даламан»/«Мармарис» на
// телефоне уходили в горизонтальную прокрутку и не занимали всю
// ширину, хотя помещались).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:island_guide/app/theme.dart';
import 'package:island_guide/features/home/presentation/widgets/scrollable_chip_rail.dart';

void main() {
  // Кария: две локации — короткие подписи, на обычном телефоне
  // (393 dp) помещаются вместе с иконкой и отступами пилюли.
  const cariaItems = [
    (id: 'dalaman', label: 'Даламан'),
    (id: 'marmaris', label: 'Мармарис'),
  ];

  Widget rail() => MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: ScrollableChipRail(
                items: cariaItems,
                activeId: 'dalaman',
                onSelect: (_) {},
                icon: Icons.anchor,
                tall: true,
              ),
            ),
          ),
        ),
      );

  List<Rect> chipRects(WidgetTester tester) => tester
      .renderObjectList<RenderBox>(find.byType(InkWell))
      .map((box) => box.localToGlobal(Offset.zero) & box.size)
      .toList();

  testWidgets('две локации занимают всю ширину ленты на телефоне',
      (tester) async {
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1.0;

    addTearDown(tester.view.reset);

    await tester.pumpWidget(rail());

    await tester.pumpAndSettle();

    // Чипы помещаются — лента НЕ уходит в горизонтальную прокрутку.
    expect(find.byType(SingleChildScrollView), findsNothing);

    final railRect = tester.getRect(find.byType(ScrollableChipRail));

    final chips = chipRects(tester);

    // Чипы + зазор между ними занимают ВСЮ ширину ленты.
    expect(
      chips[0].width + chips[1].width + 7,
      closeTo(railRect.width, 0.5),
      reason: 'мало чипов и экран позволяет — кнопки растянуты на всю '
          'ширину, справа не остаётся пустого места',
    );

    // Подписи не обрезаны: ширина текста равна естественной
    // (её замеряем на узком экране, где лента в скролле).
    final wideText1 = tester.getRect(find.text('Даламан')).width;

    final wideText2 = tester.getRect(find.text('Мармарис')).width;

    tester.view.physicalSize = const Size(320, 800);

    await tester.pumpWidget(rail());

    await tester.pumpAndSettle();

    expect(find.byType(SingleChildScrollView), findsOneWidget);

    expect(
      tester.getRect(find.text('Даламан')).width,
      moreOrLessEquals(wideText1, epsilon: 0.5),
    );

    expect(
      tester.getRect(find.text('Мармарис')).width,
      moreOrLessEquals(wideText2, epsilon: 0.5),
    );
  });

  testWidgets('на очень узком экране лента по-прежнему скроллится',
      (tester) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1.0;

    addTearDown(tester.view.reset);

    await tester.pumpWidget(rail());

    await tester.pumpAndSettle();

    // Чипы не помещаются — горизонтальная прокрутка сохраняется.
    expect(find.byType(SingleChildScrollView), findsOneWidget);
  });
}
