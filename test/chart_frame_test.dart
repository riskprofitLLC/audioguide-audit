// ChartFrame / ChartTicksPainter: двойная волосяная рамка «поля
// атласной страницы» — дефолтный воротник, радиус и засечки;
// painter переживает нулевые размеры.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:island_guide/core/widgets/chart_frame.dart';

void main() {
  test('дефолтный воротник рамки — 10', () {
    expect(ChartFrame.defaultCollar, 10);
  });

  testWidgets('рамка оборачивает содержимое', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ChartFrame(child: SizedBox(width: 100, height: 50)),
        ),
      ),
    );

    expect(find.byType(ChartFrame), findsOne);
    expect(find.byType(CustomPaint), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('воротник настраивается', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ChartFrame(collar: 0, child: SizedBox(width: 100, height: 50)),
        ),
      ),
    );

    final frame = tester.widget<ChartFrame>(find.byType(ChartFrame));
    expect(frame.collar, 0);
  });

  test('painter строится с параметрами', () {
    const painter = ChartTicksPainter(
      gap: 10,
      tickColor: Color(0xFF000000),
      corners: true,
    );
    expect(painter.gap, 10);
    expect(painter.corners, isTrue);
    // shouldRepaint — true только при смене параметров
    expect(
      painter.shouldRepaint(
        const ChartTicksPainter(
          gap: 10,
          tickColor: Color(0xFF000000),
          corners: true,
        ),
      ),
      isFalse,
    );
    expect(
      painter.shouldRepaint(
        const ChartTicksPainter(
          gap: 20,
          tickColor: Color(0xFF000000),
          corners: true,
        ),
      ),
      isTrue,
    );
  });
}
