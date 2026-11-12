// DetailBadgesRow / DetailSandBadge: ряд бейджей точки — Wrap с
// переносом, единый песочный бейдж с подписью и CAPS-вариантом.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:island_guide/core/widgets/detail_badges_row.dart';

void main() {
  testWidgets('ряд бейджей переносится, а не переполняется',
      (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DetailBadgesRow(
            spacing: 8,
            runSpacing: 8,
            children: List.generate(
              8,
              (i) => const DetailSandBadge(label: 'Бейдж'),
            ),
          ),
        ),
      ),
    );

    expect(find.byType(Wrap), findsOne);
    expect(tester.takeException(), isNull);
  });

  testWidgets('DetailSandBadge рисует подпись', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: DetailSandBadge(label: 'По воде')),
      ),
    );

    expect(find.text('По воде'), findsOne);
  });

  testWidgets('caps меняет только стиль подписи', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: DetailSandBadge(label: '2,4 км', caps: true)),
      ),
    );

    // caps — это letterSpacing токена AppText.label, а не uppercase:
    // текст остаётся как передан
    final text = tester.widget<Text>(find.text('2,4 км'));
    expect(text.style?.letterSpacing, 0.8);
  });
}
