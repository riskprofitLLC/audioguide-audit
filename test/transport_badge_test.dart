// П3 (12-й проход): тип перемещения локации — манифест
// `transport: "boat"` → бейдж «ПО ВОДЕ» у маршрутов (карточка
// главной, детали, шторка на карте) и подпись «на воде».

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:island_guide/core/widgets/app_card.dart';
import 'package:island_guide/features/content/models/manifest.dart';
import 'package:island_guide/features/trails/presentation/widgets/boat_badge.dart';

void main() {
  test('манифест разбирает transport, isBoat работает', () {
    final boat = Manifest.fromJson({
      'id': 'kekova',
      'name': 'Остров Кекова',
      'language': 'ru',
      'map': '',
      'trails': 'trails.geojson',
      'poi': 'poi.json',
      'audio': 'audio',
      'images': 'images',
      'transport': 'boat',
    });

    expect(boat.transport, 'boat');
    expect(boat.isBoat, isTrue);

    final walk = Manifest.fromJson({
      'id': 'gemiler',
      'name': 'Гемилер',
      'language': 'ru',
      'map': '',
      'trails': 'trails.geojson',
      'poi': 'poi.json',
      'audio': 'audio',
      'images': 'images',
    });

    expect(walk.transport, isNull);
    expect(walk.isBoat, isFalse);
  });

  testWidgets('BoatBadge: парусник + «ПО ВОДЕ»', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: BoatBadge())),
    );

    expect(find.text('ПО ВОДЕ'), findsOneWidget);
  });

  testWidgets('TrailCard морской локации несёт бейдж «ПО ВОДЕ» (П3)',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: TrailCard(
            title: 'Кекова с воды',
            distance: 4200,
            poiCount: 12,
            walkingTime: '≈ 1 ч на воде',
            isBoat: true,
          ),
        ),
      ),
    );

    expect(find.text('ПО ВОДЕ'), findsOneWidget);
    expect(find.text('Кекова с воды'), findsOneWidget);
    expect(find.text('≈ 1 ч на воде'), findsOneWidget);
  });

  testWidgets('TrailCard пешей локации — без бейджа', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: TrailCard(
            title: 'Маршрут по острову Гемилер',
            distance: 3500,
            poiCount: 9,
          ),
        ),
      ),
    );

    expect(find.text('ПО ВОДЕ'), findsNothing);
  });
}
