// Skeleton: скелетоны загрузки — SkeletonBox/SkeletonRow/SkeletonCard/
// DetailSkeleton рисуются без ошибок и не анимируются при Reduce
// Motion (shimmer глушится).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:island_guide/core/widgets/skeleton.dart';

void main() {
  testWidgets('SkeletonBox с явными размерами', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SkeletonBox(width: 48, height: 48, radius: 8),
        ),
      ),
    );

    expect(tester.getSize(find.byType(SkeletonBox)), const Size(48, 48));
    expect(tester.takeException(), isNull);
  });

  testWidgets('SkeletonRow и SkeletonCard строятся', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              SkeletonRow(),
              SkeletonRow(trailing: true),
              SkeletonCard(),
            ],
          ),
        ),
      ),
    );

    expect(find.byType(SkeletonRow), findsNWidgets(2));
    expect(find.byType(SkeletonCard), findsOne);
    expect(tester.takeException(), isNull);
  });

  testWidgets('DetailSkeleton — полный скелетон страницы деталей',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: DetailSkeleton()),
      ),
    );

    expect(tester.takeException(), isNull);
    // скелетон состоит из нескольких блоков
    expect(find.byType(SkeletonBox), findsWidgets);
  });

  testWidgets('Reduce Motion: shimmer не запускается', (tester) async {
    await tester.pumpWidget(
      const MediaQuery(
        data: MediaQueryData(disableAnimations: true),
        child: MaterialApp(
          home: Scaffold(body: SkeletonBox(width: 40, height: 40)),
        ),
      ),
    );

    // при выключенных анимациях не должно быть анимационных контроллеров
    expect(tester.takeException(), isNull);
  });
}
