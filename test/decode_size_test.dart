// Ширина декодирования миниатюр (decodeWidthPx).
//
// Без cacheWidth Flutter декодирует фото ~1200 px ради миниатюры
// 40 px — лишняя память и время на каждый билд списка. Логика
// маленькая, но её ошибка (неверный DPR/oversample) тихо
// возвращает полноразмерное декодирование.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:island_guide/core/utils/decode_size.dart';

void main() {
  testWidgets('умножает логическую ширину на DPR и oversample',
      (tester) async {
    tester.view.devicePixelRatio = 3.0;

    addTearDown(tester.view.reset);

    late int? result;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            result = decodeWidthPx(context, 40, oversample: 2);

            return const SizedBox();
          },
        ),
      ),
    );

    expect(result, 40 * 3 * 2);
  });

  testWidgets('oversample по умолчанию — 2', (tester) async {
    tester.view.devicePixelRatio = 1.0;

    addTearDown(tester.view.reset);

    late int? result;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            result = decodeWidthPx(context, 40);

            return const SizedBox();
          },
        ),
      ),
    );

    expect(result, 80);
  });

  testWidgets('дробная логическая ширина округляется до целых пикселей',
      (tester) async {
    tester.view.devicePixelRatio = 1.0;

    addTearDown(tester.view.reset);

    late int? result;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            result = decodeWidthPx(context, 13.5);

            return const SizedBox();
          },
        ),
      ),
    );

    expect(result, 27);
  });
}
