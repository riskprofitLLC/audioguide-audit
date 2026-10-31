import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'package:island_guide/features/content/presentation/widgets/image_gallery.dart';
import 'package:island_guide/features/map/presentation/widgets/trail_info_sheet.dart';
import 'package:island_guide/features/trails/models/trail.dart';
import 'package:island_guide/features/trails/models/trail_point.dart';

import 'support/test_database.dart';

void main() {
  // Звезда избранного в шторке маршрута (P1-3) читает
  // контроллер избранного — нужна тестовая база.
  initTestDatabase();

  const trail = Trail(
    id: 'trail-01',
    name: 'Тропа к мысу',
    description: 'Описание маршрута',
    distance: 3081,
    points: [
      TrailPoint(id: '0', latitude: 43.0, longitude: 131.9, order: 0),
    ],
  );

  testWidgets('TrailInfoSheet показывает галерею и стрелки', (tester) async {

    // Стрелки галереи — десктопный режим (B8): на touch их заменяет
    // свайп. Сброс инварианта — до tearDown-колбэков.
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;

    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: TrailInfoSheet(
            trail: trail,
            islandId: 'gemiler',
            imagePaths: [
                'poi-01/poi-01-1.jpg',
                'poi-01/poi-01-2.jpg',
              ],
            poiCount: 9,
            cascadeKeys: [
              'gemiler/poi-01',
              'gemiler/poi-02',
            ],
          ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Тропа к мысу'), findsOneWidget);
    expect(find.byType(ImageGallery), findsOneWidget);

    expect(
      find.byIcon(LucideIcons.chevronRight),
      findsOneWidget,
    );

    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('шторка маршрута не закрывает весь экран', (tester) async {
    // Шторка не поднимается выше 70% высоты окна — сверху всегда
    // остаётся видимый участок карты. Окно 400×300: контент
    // заведомо выше, панель упирается ровно в ограничение.
    tester.view.physicalSize = const Size(400, 300);
    tester.view.devicePixelRatio = 1.0;

    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: TrailInfoSheet(
              trail: trail,
              islandId: 'gemiler',
              imagePaths: [
                'poi-01/poi-01-1.jpg',
                'poi-01/poi-01-2.jpg',
              ],
              poiCount: 9,
              cascadeKeys: [
                'gemiler/poi-01',
                'gemiler/poi-02',
              ],
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(
      tester.getRect(find.byType(TrailInfoSheet)).height,
      closeTo(300 * 0.7, 0.5),
      reason: 'шторка маршрута занимает не больше 70% высоты экрана',
    );
  });
}
