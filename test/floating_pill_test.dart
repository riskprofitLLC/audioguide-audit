// FloatingPill (D2): единый каркас плавающих пилюль — тап-цель ≥44,
// семантика кнопки, tooltip не дублируется в семантику, leading
// заменяет круг с иконкой, FloatingPillShow глушит тапы и прячет
// содержимое.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:island_guide/core/widgets/floating_pill.dart';

Widget host(Widget child) => MaterialApp(
      home: Scaffold(
        body: Center(child: child),
      ),
    );

void main() {
  testWidgets('пилюля держит тап-цель ≥44 и зовёт onTap', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      host(
        FloatingPill(
          icon: Icons.place,
          semanticsLabel: 'Погода',
          onTap: () => taps++,
          child: const Text('+24°'),
        ),
      ),
    );

    final box = tester.getSize(find.byType(FloatingPill));
    expect(box.height, greaterThanOrEqualTo(44));

    await tester.tap(find.byType(FloatingPill));
    expect(taps, 1);
  });

  testWidgets('семантика — кнопка с меткой, tooltip вне семантики',
      (tester) async {
    await tester.pumpWidget(
      host(
        FloatingPill(
          icon: Icons.info,
          semanticsLabel: 'Рядом: бухта',
          tooltip: 'Слушать',
          onTap: () {},
          child: const Text('Рядом'),
        ),
      ),
    );

    final node = tester.getSemantics(find.byType(FloatingPill));
    expect(node.flagsCollection.isButton, isTrue);
    expect(node.label, contains('Рядом: бухта'));
    // тултип исключён из семантики — метка не задваивается
    expect(node.label, isNot(contains('Слушать')));
    expect(find.byTooltip('Слушать'), findsOne);
  });

  testWidgets('без onTap пилюля не интерактивна', (tester) async {
    await tester.pumpWidget(
      host(
        const FloatingPill(
          icon: Icons.info,
          semanticsLabel: 'Плашка',
          child: Text('Текст'),
        ),
      ),
    );

    final node = tester.getSemantics(find.byType(FloatingPill));
    expect(node.flagsCollection.isButton, isFalse);
  });

  testWidgets('leading заменяет круг с иконкой', (tester) async {
    await tester.pumpWidget(
      host(
        const FloatingPill(
          leading: SizedBox(key: Key('cover'), width: 36, height: 36),
          child: Text('Играет'),
        ),
      ),
    );

    expect(find.byKey(const Key('cover')), findsOne);
  });

  testWidgets('FloatingPillShow скрывает содержимое и глушит тапы',
      (tester) async {
    await tester.pumpWidget(
      host(
        const FloatingPillShow(
          visible: false,
          child: FloatingPill(icon: Icons.info, child: Text('X')),
        ),
      ),
    );

    expect(
      tester
          .widget<IgnorePointer>(
            find.descendant(
              of: find.byType(FloatingPillShow),
              matching: find.byType(IgnorePointer),
            ),
          )
          .ignoring,
      isTrue,
    );

    await tester.pumpAndSettle();
    final opacity = tester.widget<AnimatedOpacity>(
      find.descendant(
        of: find.byType(FloatingPillShow),
        matching: find.byType(AnimatedOpacity),
      ),
    );
    expect(opacity.opacity, 0);
  });

  testWidgets('FloatingPillShow показывает содержимое когда visible',
      (tester) async {
    await tester.pumpWidget(
      host(
        const FloatingPillShow(
          visible: true,
          child: FloatingPill(icon: Icons.info, child: Text('X')),
        ),
      ),
    );

    await tester.pumpAndSettle();
    final opacity = tester.widget<AnimatedOpacity>(
      find.descendant(
        of: find.byType(FloatingPillShow),
        matching: find.byType(AnimatedOpacity),
      ),
    );
    expect(opacity.opacity, 1);
    expect(
      tester
          .widget<IgnorePointer>(
            find.descendant(
              of: find.byType(FloatingPillShow),
              matching: find.byType(IgnorePointer),
            ),
          )
          .ignoring,
      isFalse,
    );
  });
}
