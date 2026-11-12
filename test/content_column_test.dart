// ContentColumn: ограничение ширины статьи (6-й проход) — только
// через Expanded → Align(topLeft) → ConstrainedBox, иначе
// maxWidth не работает под tight-констрейнтом.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:island_guide/core/widgets/content_column.dart';

void main() {
  test('максимальная ширина — 720', () {
    expect(ContentColumn.maxWidth, 720);
  });

  testWidgets('колонка не шире 720 на широком экране', (tester) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Row(
            children: [
              Expanded(
                child: Align(
                  alignment: Alignment.topLeft,
                  child: ContentColumn(
                    child: SizedBox(
                      key: Key('inner'),
                      width: double.infinity,
                      height: 10,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    // обёртка Center тянется на всю ширину — ограничение несёт
    // дочерний блок
    final inner = tester.getSize(find.byKey(const Key('inner')));
    expect(inner.width, lessThanOrEqualTo(720));
  });

  testWidgets('на узком экране колонка занимает всю доступную ширину',
      (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Row(
            children: [
              Expanded(
                child: Align(
                  alignment: Alignment.topLeft,
                  child: ContentColumn(
                    child: SizedBox(
                      key: Key('inner'),
                      width: double.infinity,
                      height: 10,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    final inner = tester.getSize(find.byKey(const Key('inner')));
    expect(inner.width, 360);
  });
}
