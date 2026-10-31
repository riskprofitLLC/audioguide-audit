// A10.3 (8-й проход): кеш замеров ширины чипов ScrollableChipRail
// инвалидируется при смене textScale (в ключе уже есть скейл) —
// проверяем, что при увеличении масштаба текста замер идёт заново
// и чип РЕАЛЬНО шире, а не берётся из кеша старого масштаба.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:island_guide/app/theme.dart';
import 'package:island_guide/features/home/presentation/widgets/scrollable_chip_rail.dart';

void main() {
  testWidgets('textScale 1.6 даёт более широкие чипы (A10.3)',
      (tester) async {
    tester.view.physicalSize = const Size(300, 400);
    tester.view.devicePixelRatio = 1.0;

    addTearDown(tester.view.reset);

    const items = [
      (id: 'a', label: 'Залив Фетхие'),
      (id: 'b', label: 'Ликия'),
    ];

    var scaler = const TextScaler.linear(1.0);

    Widget build() => MediaQuery(
          data: MediaQueryData(textScaler: scaler),
          child: MaterialApp(
            theme: AppTheme.light,
            home: Scaffold(
              body: Center(
                // Узкий контейнер: чипы не помещаются — лента
                // уходит в горизонтальный скролл, и чипы принимают
                // ЕСТЕСТВЕННУЮ (замеренную) ширину.
                child: SizedBox(
                  width: 200,
                  child: ScrollableChipRail(
                    items: items,
                    activeId: 'a',
                    onSelect: (_) {},
                  ),
                ),
              ),
            ),
          ),
        );

    await tester.pumpWidget(build());

    await tester.pumpAndSettle();

    final widthSmall =
        tester.getSize(find.text('Залив Фетхие').first).width;

    expect(widthSmall, greaterThan(0));

    // Другой масштаб текста: ключ кеша меняется, замер идёт заново.
    scaler = const TextScaler.linear(1.6);

    await tester.pumpWidget(build());

    await tester.pumpAndSettle();

    final widthBig =
        tester.getSize(find.text('Залив Фетхие').first).width;

    expect(
      widthBig,
      greaterThan(widthSmall),
      reason: 'кеш замеров ширин чипов ключуется по textScale — при '
          'смене масштаба замер выполняется заново и чипы реально '
          'шире (A10.3)',
    );
  });
}
