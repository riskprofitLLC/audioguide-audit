// Единый баннер «Пешие маршруты запрещены» (31-й проход).
//
// Раньше это были две копии в home_page и map_page с РАЗНЫМ текстом
// по умолчанию — один и тот же случай читался по-разному.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:island_guide/core/widgets/hiking_forbidden_notice.dart';

void main() {
  Future<void> pump(WidgetTester tester, Widget child) async {
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: child)),
    );

    await tester.pumpAndSettle();
  }

  testWidgets('без trailNotice — стандартная формулировка', (tester) async {
    await pump(tester, const HikingForbiddenNotice());

    expect(find.text('Пешие маршруты запрещены'), findsOneWidget);

    expect(find.text(kHikingForbiddenNotice), findsOneWidget);
  });

  testWidgets('trailNotice из манифеста перекрывает стандартный текст',
      (tester) async {
    await pump(
      tester,
      const HikingForbiddenNotice(notice: 'Свой текст предупреждения.'),
    );

    expect(find.text('Свой текст предупреждения.'), findsOneWidget);

    expect(find.text(kHikingForbiddenNotice), findsNothing);
  });

  testWidgets('карта: компактный вариант с плавающей тенью', (tester) async {
    await pump(
      tester,
      const HikingForbiddenNotice(compact: true, floating: true),
    );

    expect(find.text('Пешие маршруты запрещены'), findsOneWidget);

    // Компактный вариант — тот же каркас NoticeBanner, но плотнее:
    // заголовок и текст на месте, баннер отрисован.
    expect(find.byType(HikingForbiddenNotice), findsOneWidget);
  });
}
