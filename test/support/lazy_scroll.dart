import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// Прокручивает ленивый скролл-вьюпорт, пока [target] не будет
/// построен (ленивые SliverList строят только видимые элементы,
/// а `scrollUntilVisible` драгает по центру экрана — там может
/// лежать непрокручиваемая область, например превью карты с
/// opaque-жестом).
///
/// Используется тестами главного экрана (B15): контент списков
/// больше не строится целиком, «доехать» до элемента жестом
/// нельзя — скроллим позицию программно. Прокрутка мгновенная
/// (без duration): ожидаемый `moveTo` с анимацией под FakeAsync
/// не завершается — кадры качает только pump.
Future<void> scrollLazyUntilVisible(
  WidgetTester tester,
  Finder target, {
  Finder? scrollable,
  double step = 400,
  int maxSteps = 60,
}) async {
  final view = scrollable ?? find.byType(Scrollable).first;

  final state = tester.state<ScrollableState>(view);

  for (var i = 0; i < maxSteps; i++) {
    if (target.evaluate().isNotEmpty) {
      return;
    }

    final position = state.position;

    if (!position.hasContentDimensions) {
      await tester.pump();

      continue;
    }

    final next = (position.pixels + step).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );

    if (next == position.pixels) {
      // Упёрлись в край (min/max), а цели нет — скроллить некуда.
      return;
    }

    await position.moveTo(next);

    await tester.pumpAndSettle();
  }
}
