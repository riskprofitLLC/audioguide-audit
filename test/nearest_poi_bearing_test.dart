// П2 (12-й проход): чип ближайшей точки — стрелка повёрнута
// азимутом на точку, рядом компасный румб.
//
// A3 (17-й проход): глиф navigation2 — остриём на СЕВЕР при
// нулевом повороте. Старый LucideIcons.navigation нарисован
// остриём на северо-восток (наследие Feather) — направление
// врало на 45°. Тест фиксирует ВИЗУАЛЬНОЕ направление
// эталонными поворотами: север — без поворота, восток — 90°.
//
// B4 (18-й проход): стрелка всегда показывает направление
// ОТНОСИТЕЛЬНО ЭКРАНА карты — азимут минус bearing камеры
// (north-up: bearing 0 — абсолютный азимут; course-up —
// «куда на экране»). Румб в подписи остаётся абсолютным;
// семантика объявляет «стрелка указывает на точку».

import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'package:island_guide/features/map/presentation/widgets/nearest_poi_chip.dart';

void main() {
  testWidgets('стрелка navigation2 повёрнута азимутом, румб подписан (П2/A3)',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: NearestPoiChip(
              title: 'Маяк',
              distance: 350,
              bearing: 315,
            ),
          ),
        ),
      ),
    );

    // Глиф — navigation2 (остриё вверх), НЕ navigation (остриё на
    // северо-восток, врало на 45°).
    expect(find.byIcon(LucideIcons.navigation2), findsOneWidget);
    expect(find.byIcon(LucideIcons.navigation), findsNothing);

    // Стрелка повёрнута на 315° (северо-запад) — матрица ровно
    // rotationZ(315°).
    final rotate = tester.widget<Transform>(
      find.ancestor(
        of: find.byIcon(LucideIcons.navigation2),
        matching: find.byType(Transform),
      ).first,
    );

    expect(
      rotate.transform,
      equals(Matrix4.rotationZ(315 * pi / 180)),
    );

    // Румб подписан рядом с дистанцией (в дистанции —
    // неразрывный пробел, поэтому regexp).
    expect(find.textContaining(RegExp('350.*м')), findsOneWidget);
    expect(find.textContaining('на северо-запад'), findsOneWidget);
  });

  testWidgets('визуальные эталоны направления: север без поворота, восток 90°',
      (tester) async {
    Future<Matrix4> rotationOf({double? bearing}) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: NearestPoiChip(
                title: 'Маяк',
                distance: 350,
                bearing: bearing,
              ),
            ),
          ),
        ),
      );

      final rotate = tester.widget<Transform>(
        find.ancestor(
          of: find.byIcon(LucideIcons.navigation2),
          matching: find.byType(Transform),
        ).first,
      );

      return rotate.transform;
    }

    // Точные эталоны: Flutter снапит четвертные повороты
    // (Transform.rotate → _computeRotation) — сравниваем с ними,
    // а не с шумом Matrix4.rotationZ.
    final exactEast = Matrix4.zero()
      ..setEntry(0, 1, -1.0)
      ..setEntry(1, 0, 1.0)
      ..setEntry(2, 2, 1.0)
      ..setEntry(3, 3, 1.0);

    // Север (0°) — стрелка смотрит вверх без поворота.
    expect(await rotationOf(bearing: 0), equals(Matrix4.identity()));

    // Восток (90°) — поворот на 90° по часовой.
    expect(await rotationOf(bearing: 90), equals(exactEast));
  });

  testWidgets('повёрнутая карта — стрелка относительно экрана (B4)',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: NearestPoiChip(
              title: 'Маяк',
              distance: 350,
              // Точка на север, карта повёрнута на восток (bearing
              // 90) — на экране точка слева: стрелка указывает влево.
              bearing: 0,
              mapBearing: 90,
            ),
          ),
        ),
      ),
    );

    final rotate = tester.widget<Transform>(
      find.ancestor(
        of: find.byIcon(LucideIcons.navigation2),
        matching: find.byType(Transform),
      ).first,
    );

    // Точный эталон 270° (четвертной поворот — Flutter снапит).
    final exactWest = Matrix4.zero()
      ..setEntry(0, 1, 1.0)
      ..setEntry(1, 0, -1.0)
      ..setEntry(2, 2, 1.0)
      ..setEntry(3, 3, 1.0);

    expect(
      rotate.transform,
      equals(exactWest),
      reason: 'азимут 0° при повороте карты 90° — стрелка влево (270°)',
    );

    // Румб подписи — абсолютный, от поворота карты не зависит.
    expect(find.textContaining('на север'), findsOneWidget);
  });

  testWidgets('семантика: стрелка указывает на точку (B4)', (tester) async {
    final semantics = tester.ensureSemantics();

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: NearestPoiChip(
              title: 'Маяк',
              distance: 350,
              bearing: 315,
            ),
          ),
        ),
      ),
    );

    expect(
      find.bySemanticsLabel(RegExp('Ближайшая точка: Маяк.*'
          'Стрелка указывает на точку')),
      findsOneWidget,
    );

    semantics.dispose();
  });

  testWidgets('без азимута — статичная стрелка, румба нет (П2)',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: NearestPoiChip(
              title: 'Маяк',
              distance: 350,
            ),
          ),
        ),
      ),
    );

    expect(find.textContaining('на северо-запад'), findsNothing);
    expect(find.textContaining('на север'), findsNothing);
  });
}
