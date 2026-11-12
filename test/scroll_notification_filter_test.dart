// Тест фильтра scroll-уведомлений на страницах деталей (A1):
// горизонтальный PageView галереи внутри вертикального списка не
// должен попадать в слушатель параллакса/шапки.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Копия слушателя страниц деталей: считает уведомления,
// прошедшие фильтр `axis == vertical && depth == 0`.
class _DetailLikeScrollListener extends StatefulWidget {
  const _DetailLikeScrollListener({required this.onVerticalScroll});

  final ValueChanged<double> onVerticalScroll;

  @override
  State<_DetailLikeScrollListener> createState() =>
      _DetailLikeScrollListenerState();
}

class _DetailLikeScrollListenerState
    extends State<_DetailLikeScrollListener> {
  @override
  Widget build(BuildContext context) {
    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification.metrics.axis != Axis.vertical ||
            notification.depth != 0) {
          return false;
        }
        widget.onVerticalScroll(notification.metrics.pixels);
        return false;
      },
      child: ListView(
        children: [
          // «Галерея»: горизонтальный PageView, как hero в деталях.
          SizedBox(
            height: 220,
            child: PageView(
              children: List.generate(
                20,
                (i) => ColoredBox(
                  color: Colors.blue.shade100,
                  child: Center(child: Text('photo $i')),
                ),
              ),
            ),
          ),
          // Длинный вертикальный контент.
          for (var i = 0; i < 60; i++) ListTile(title: Text('row $i')),
        ],
      ),
    );
  }
}

void main() {
  testWidgets('свайп галереи не попадает в вертикальный слушатель (A1)',
      (tester) async {
    final verticalEvents = <double>[];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: _DetailLikeScrollListener(
            onVerticalScroll: verticalEvents.add,
          ),
        ),
      ),
    );

    // Горизонтальный свайп галереи (PageView).
    await tester.drag(
      find.byType(PageView),
      const Offset(-300, 0),
    );

    await tester.pumpAndSettle();

    expect(verticalEvents, isEmpty,
        reason: 'горизонтальные уведомления PageView фильтруются');

    // Горизонтальный drag НАКЛОННЫЙ (пара градусов) не считается
    // вертикальным скроллом списка: ось метрики остаётся
    // горизонтальной.
    await tester.drag(
      find.byType(PageView),
      const Offset(-300, -6),
    );

    await tester.pumpAndSettle();

    expect(verticalEvents, isEmpty,
        reason: 'наклонный свайп галереи — всё ещё её ось');

    // Вертикальный скролл списка — события доходят.
    await tester.drag(
      find.text('row 3'),
      const Offset(0, -250),
    );

    await tester.pumpAndSettle();

    expect(verticalEvents, isNotEmpty,
        reason: 'вертикальный скролл списка проходит фильтр');
  });
}
