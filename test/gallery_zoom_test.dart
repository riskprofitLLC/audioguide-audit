// Зум полноэкранной галереи (P0-9, 6-й проход):
//  - двойной тап переключает 1× ↔ 2.5×;
//  - у КАЖДОЙ страницы свой TransformationController (раньше
//    один контроллер делили все страницы — соседние кадры во
//    время свайпа получали тот же масштаб);
//  - при зуме PageView получает NeverScrollableScrollPhysics:
//    пан увеличенного фото не конфликтует с листанием.
//
// Листание проверяется флингом: flingFrom шлёт 50+ мелких
// шагов (~7 px) — как настоящий поток событий пальца, и
// HorizontalDrag PageView первым пересекает свой slop (18 px
// в тестах, 8 px на Android), раньше ScaleGestureRecognizer
// InteractiveViewer (pan slop 36/16 px). Пошаговый moveBy с
// крупным шагом (≥ 36 px) съедается scale-ареной: InteractiveViewer
// глубже PageView в хит-тесте, видит событие первым и мгновенно
// self-declared winner — это артефакт гранулярности теста, на
// устройстве медленный драг листает нормально.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:island_guide/features/content/presentation/widgets/image_gallery.dart';

void main() {
  Future<void> openFullscreen(WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
        home: Scaffold(
          body: ImageGallery(
            imagePaths: [
              'poi-01/poi-01-1.jpg',
              'poi-01/poi-01-2.jpg',
              'poi-01/poi-01-3.jpg',
            ],
            islandId: 'gemiler',
            height: 200,
          ),
        ),
      ),
      )
    );

    await tester.pumpAndSettle();

    await tester.tap(find.byType(ImagePlaceholder).first);
    await tester.pumpAndSettle();
  }

  Future<void> doubleTapAt(WidgetTester tester, Offset center) async {
    await tester.tapAt(center);
    await tester.pump(const Duration(milliseconds: 80));
    await tester.tapAt(center);
    await tester.pumpAndSettle();
  }

  InteractiveViewer currentViewer(WidgetTester tester) =>
      tester.widget<InteractiveViewer>(find.byType(InteractiveViewer).first);

  double currentScale(WidgetTester tester) =>
      currentViewer(tester)
          .transformationController!
          .value
          .getMaxScaleOnAxis();

  testWidgets('двойной тап: 1× ↔ 2.5×, зум блокирует листание',
      (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;

    addTearDown(tester.view.reset);

    await openFullscreen(tester);

    // Счётчик «1 / 3» — два: фуллскрин + всегда видимый штамп
    // карусели позади (штамп теперь виден и у коротких галерей).
    expect(find.text('1 / 3'), findsNWidgets(2));

    final center = tester.getCenter(find.byType(InteractiveViewer).first);

    // До зума физика листания обычная.
    expect(
      tester.widget<PageView>(find.byType(PageView).last).physics,
      isNull,
    );

    await doubleTapAt(tester, center);

    expect(currentScale(tester), closeTo(2.5, 0.01),
        reason: 'двойной тап — зум 2.5×');

    // Увеличенный кадр не листается: PageView физика отключена,
    // пальцем панорамируется фото (раньше пан конфликтовал
    // с перелистыванием).
    expect(
      tester.widget<PageView>(find.byType(PageView).last).physics,
      isA<NeverScrollableScrollPhysics>(),
    );

    // Пошаговый свайп (moveBy + pump, см. AGENTS.md) не листает
    // увеличенную страницу.
    final gesture = await tester.startGesture(center);

    for (var i = 0; i < 6; i++) {
      await gesture.moveBy(const Offset(-60, 0));
      await tester.pump();
    }

    await gesture.up();
    await tester.pumpAndSettle();

    expect(find.text('1 / 3'), findsNWidgets(2),
        reason: 'увеличенный кадр не листается');

    // Повторный двойной тап — обратно 1×, листание возвращается.
    await doubleTapAt(tester, center);

    expect(currentScale(tester), closeTo(1.0, 0.01),
        reason: 'двойной тап — зум 1×');

    expect(
      tester.widget<PageView>(find.byType(PageView).last).physics,
      isNull,
    );

    // После возврата 1× страницы листаются (флинг доходит до
    // PageView).
    await tester.fling(
      find.byType(InteractiveViewer).first,
      const Offset(-350, 0),
      800,
    );

    await tester.pumpAndSettle();

    expect(find.text('2 / 3'), findsOneWidget,
        reason: 'после сброса зума листание работает');
  });

  testWidgets('зум у каждой страницы свой: соседний кадр не наследует',
      (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;

    addTearDown(tester.view.reset);

    await openFullscreen(tester);

    // Зумим первый кадр и возвращаем 1×.
    final firstCenter =
        tester.getCenter(find.byType(InteractiveViewer).first);

    await doubleTapAt(tester, firstCenter);
    await doubleTapAt(tester, firstCenter);

    // Флинг на второй кадр.
    await tester.fling(
      find.byType(InteractiveViewer).first,
      const Offset(-350, 0),
      800,
    );

    await tester.pumpAndSettle();

    expect(find.text('2 / 3'), findsOneWidget);

    // Второй кадр — свой контроллер с единичной матрицей:
    // соседние кадры не наследуют зум (общий контроллер раньше
    // растягивал их во время свайпа).
    expect(
      currentScale(tester),
      closeTo(1.0, 0.01),
      reason: 'новая страница начинается с 1×',
    );

    // Зумим второй кадр — он увеличивается независимо.
    final secondCenter =
        tester.getCenter(find.byType(InteractiveViewer).first);

    await doubleTapAt(tester, secondCenter);

    expect(currentScale(tester), closeTo(2.5, 0.01),
        reason: 'кадр зумится независимо от соседнего');
  });
}
