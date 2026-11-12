import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:island_guide/core/widgets.dart';
import 'package:island_guide/features/trails/utils/format_distance.dart';

void main() {
  group('formatTrailDistance (метры → человекочитаемая строка)', () {
    test('3081 м → «3,1 км» (запятая, неразрывный пробел)', () {
      expect(formatTrailDistance(3081), '3,1\u00A0км');
    });

    test('500 м → «500 м»', () {
      expect(formatTrailDistance(500), '500\u00A0м');
    });

    test('999 м → «999 м» (граница без перевода в км)', () {
      expect(formatTrailDistance(999), '999\u00A0м');
    });

    test('1000 м → «1,0 км»', () {
      expect(formatTrailDistance(1000), '1,0\u00A0км');
    });

    test('null → «Длина неизвестна»', () {
      expect(formatTrailDistance(null), 'Длина неизвестна');
    });
  });

  group('TrailCard принимает длину в МЕТРАХ', () {
    testWidgets('3081 м показывается как «3,1 КМ», а не «3081.0 КМ»', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: TrailCard(
              title: 'Маршрут',
              distance: 3081,
              poiCount: 5,
            ),
          ),
        ),
      );

      expect(find.text('3,1\u00A0КМ'), findsOneWidget);
      expect(find.textContaining('3081'), findsNothing);
    });

    testWidgets('null расстояние — бейдж «ДЛИНА НЕИЗВЕСТНА»', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: TrailCard(
              title: 'Маршрут',
              distance: null,
              poiCount: 5,
            ),
          ),
        ),
      );

      expect(find.text('ДЛИНА НЕИЗВЕСТНА'), findsOneWidget);
    });
  });
}
