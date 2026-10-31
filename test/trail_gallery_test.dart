// P1-3 (7-й проход): галерея маршрута собирает фото ТОЛЬКО его
// точек. Раньше страница маршрута брала фото всех POI локации —
// 37 фото внемаршрутных точек Гемилера (poi-10/12/13) попадали
// в «галерею маршрута», а обложка TrailCard почти никогда не
// совпадала с первым кадром, и hero-полёт отключался.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:island_guide/features/content/presentation/widgets/image_gallery.dart';
import 'package:island_guide/features/content/providers/content_providers.dart';
import 'package:island_guide/features/trails/presentation/pages/trail_detail_page.dart';
import 'package:island_guide/features/trails/utils/trail_gallery.dart';

import 'support/test_database.dart';

void main() {
  initTestDatabase();

  test('хелпер: кадры галереи — только фото точек маршрута', () async {
    final container = ProviderContainer(
      overrides: [
        currentIslandIdProvider.overrideWith((_) => 'gemiler'),
      ],
    );

    addTearDown(container.dispose);

    final pois = await container.read(poisFamily('gemiler').future);

    final images = trailGalleryImages(pois, 'trail-01');

    // Инвариант (Б14, замечание Sonnet): кадры галереи — это в
    // ТОЧНОСТИ сумма фото маршрутных точек; жёсткое число ломалось
    // при любом изменении контента.
    final expectedCount = pois
        .where((p) => p.trailIds.contains('trail-01'))
        .fold<int>(0, (sum, poi) => sum + poi.imagePaths.length);

    expect(images.length, expectedCount,
        reason: 'в галерее — все фото маршрутных точек и ничего больше');

    // Ни одного кадра внемаршрутных POI.
    final offRouteImages = <String>{
      for (final poi in pois.where((p) => p.trailIds.isEmpty))
        ...poi.imagePaths,
    };

    expect(
      images.any(offRouteImages.contains),
      isFalse,
      reason: 'фото poi-10/12/13 не попадают в галерею маршрута',
    );

    // Обложка — первый кадр этой же галереи (hero совпадает).
    final cover = trailCoverAssetPath(pois, 'trail-01', 'gemiler');

    expect(cover, endsWith(images.first),
        reason: 'обложка = первый кадр галереи, hero-полёт работает');
  });

  testWidgets('страница маршрута: галерея с hero-тегом первого кадра',
      (tester) async {
    final container = ProviderContainer(
      overrides: [
        currentIslandIdProvider.overrideWith((_) => 'gemiler'),
      ],
    );

    addTearDown(container.dispose);
    addTearDown(tester.view.reset);

    // Инвариант (Б14): считаем в runAsync — после rootBundle.clear()
    // poi.json (57 КБ) под FakeAsync не читается.
    var expectedCount = 0;

    await tester.runAsync(() async {
      final pois = await container.read(poisFamily('gemiler').future);
      await container.read(trailsFamily('gemiler').future);

      expectedCount = pois
          .where((p) => p.trailIds.contains('trail-01'))
          .fold<int>(0, (sum, poi) => sum + poi.imagePaths.length);
    });

    rootBundle.clear();

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: TrailDetailPage(
            trailId: 'trail-01',
            islandId: 'gemiler',
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    final gallery = tester.widget<ImageGallery>(
      find.byType(ImageGallery),
    );

    expect(gallery.imagePaths, isNotEmpty);

    // Инвариант (Б14): «число кадров = сумма imagePaths точек
    // маршрута» — как в seeder_test, вместо жёстких 229.
    expect(
      gallery.imagePaths.length,
      expectedCount,
      reason: 'только фото точек маршрута, без внемаршрутных',
    );

    expect(
      gallery.heroTag,
      'trail-image-gemiler-trail-01',
      reason: 'hero-тег совпадает с обложкой TrailCard: полёт работает',
    );

    // Лимит кадров (B3.6, как на деталях POI): карусель из 229
    // кадров (Гемилер) листать нереально — 12 кадров + плитка
    // «Все фото (N)». Полный список остаётся в imagePaths:
    // фуллскрин из карусели открывает ВСЕ кадры.
    expect(gallery.maxCarouselFrames, 12);
  });
}
