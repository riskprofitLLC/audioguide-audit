// Тесты показа «ближних» объектов на карте: порог дистанции и
// форматирование метров в км.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:island_guide/features/map/presentation/widgets/nearest_poi_chip.dart';
import 'package:island_guide/features/map/presentation/widgets/trail_navigation_card.dart';
import 'package:island_guide/features/map/utils/nearby_display.dart';
import 'package:island_guide/features/gps/services/trail_navigator.dart';
import 'package:island_guide/features/trails/models/trail.dart';
import 'package:island_guide/features/trails/models/trail_point.dart';

Trail _trail() => const Trail(
      id: 'trail-01',
      name: 'Тропа',
      points: [
        TrailPoint(id: 'p0', latitude: 36.0, longitude: 29.0, order: 0),
        TrailPoint(id: 'p1', latitude: 36.01, longitude: 29.0, order: 1),
      ],
    );

TrailNavigationState _state({required double distance}) =>
    TrailNavigationState(
      trail: _trail(),
      distanceToTrack: distance,
      offRoute: distance > 30,
      bearing: 120,
    );

void main() {
  group('withinNearbyDisplayRadius', () {
    test('объект в пределах 2.5 км — «ближний», показываем', () {
      expect(withinNearbyDisplayRadius(0), isTrue);
      expect(withinNearbyDisplayRadius(2500), isTrue);
    });

    test('дальше 2.5 км чип скрываем', () {
      expect(withinNearbyDisplayRadius(2501), isFalse);
      expect(withinNearbyDisplayRadius(120000), isFalse,
          reason: 'в режиме «все регионы» без порога чип показывал '
              '«Отклонение 120000 м»');
      expect(withinNearbyDisplayRadius(null), isFalse);
    });
  });

  group('форматирование дистанции в км', () {
    testWidgets('NearestPoiChip: 3200 м → «3.2 км»', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: NearestPoiChip(title: 'Мыс', distance: 3200),
          ),
        ),
      );

      expect(find.text('3,2\u00A0км'), findsOneWidget);
      expect(find.text('3200\u00A0м'), findsNothing);
    });

    testWidgets('TrailNavigationCard: отклонение 1234 м → «1.2 км»',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TrailNavigationCard(state: _state(distance: 1234)),
          ),
        ),
      );

      expect(find.textContaining('1,2\u00A0км'), findsOneWidget);
      expect(find.textContaining('1234'), findsNothing);
    });

    testWidgets('TrailNavigationCard: близко — метры, не «0.0 км»',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TrailNavigationCard(state: _state(distance: 250)),
          ),
        ),
      );

      expect(find.textContaining('250\u00A0м'), findsOneWidget);
    });
  });
}
