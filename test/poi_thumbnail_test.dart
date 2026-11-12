// PoiThumbnail: миниатюра точки — номер поверх фото, фолбэк на
// глиф категории без фото, размер настраивается.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:island_guide/core/widgets/poi_thumbnail.dart';

void main() {
  testWidgets('номер отображается поверх миниатюры', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: PoiThumbnail(
            imagePath: null,
            number: 7,
            size: 48,
          ),
        ),
      ),
    );

    expect(find.text('7'), findsOne);
  });

  testWidgets('без номера — только миниатюра', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: PoiThumbnail(
            imagePath: null,
            size: 48,
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
  });

  testWidgets('размер задаётся параметром', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: PoiThumbnail(
            imagePath: null,
            size: 72,
          ),
        ),
      ),
    );

    final box = tester.getSize(
      find.byType(PoiThumbnail),
    );
    expect(box.width, lessThanOrEqualTo(72));
    expect(box.height, lessThanOrEqualTo(72));
  });
}
