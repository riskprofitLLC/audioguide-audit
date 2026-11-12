// Регрессия «шторка сверху»: горизонтальный свайп hero-галереи
// на странице POI не должен раскрывать верхнюю шапку
// (StickyAppBar) — только вертикальная прокрутка страницы.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:island_guide/features/audio/providers/audio_player_provider.dart';
import 'package:island_guide/features/audio/services/audio_player_service.dart';
import 'package:island_guide/features/content/providers/content_providers.dart';
import 'package:island_guide/features/poi/presentation/pages/poi_detail_page.dart';

import 'fakes/fake_audio_gateway.dart';
import 'support/test_database.dart';

void main() {
  initTestDatabase();

  // Сигналы состояния: шапка раскрыта, когда плавающие кнопки
  // (звезда/дерево) сняты со страницы и остаётся только кнопка
  // дерева внутри самой шапки.
  bool barShown(WidgetTester tester) =>
      tester.widgetList<Tooltip>(
        find.byTooltip('Навигация по проекту'),
      ).length == 1;

  testWidgets('листание фото не раскрывает шапку, скролл страницы — раскрывает',
      (tester) async {
    // Телефонная раскладка (<600 px): hero-галерея — первый
    // ребёнок ListView, шапка появляется после 100 px прокрутки.
    tester.view
      ..physicalSize = const Size(780, 1688) // 390x844 @2x
      ..devicePixelRatio = 2.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final gateway = FakeAudioGateway();
    final service = AudioPlayerService(gateway: gateway);
    final container = ProviderContainer(
      overrides: [audioPlayerServiceProvider.overrideWithValue(service)],
    );
    addTearDown(container.dispose);

    // poi.json Гемилера (~55 КБ) не грузится под FakeAsync —
    // сеем контент в runAsync (паттерн poi_detail_page_audio_test).
    // Число РЕАЛЬНЫХ кадров — инвариант из контента (D5: плитка
    // «Все фото» кадром не считается, счётчик — как в fullscreen).
    var realFrames = 0;

    await tester.runAsync(() async {
      final pois = await container.read(poisFamily('gemiler').future);

      final poi = pois.firstWhere((p) => p.id == 'poi-02');

      realFrames =
          poi.imagePaths.length + (poi.videoPath != null ? 1 : 0);
    });
    rootBundle.clear();

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: PoiDetailPage(poiId: 'poi-02', islandId: 'gemiler'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Стартовая страница: шапка скрыта, открыт первый кадр.
    expect(barShown(tester), isFalse);
    expect(find.text('1 / $realFrames'), findsOneWidget);

    // Чистый горизонтальный свайп влево.
    await tester.drag(find.byType(PageView), const Offset(-350, 0));
    await tester.pumpAndSettle();
    expect(find.text('2 / $realFrames'), findsOneWidget);
    expect(barShown(tester), isFalse,
        reason: 'чистый горизонтальный свайп не должен раскрывать шапку');

    // Наклонный свайп (несколько градусов вниз) — всё ещё ось
    // галереи.
    await tester.drag(find.byType(PageView), const Offset(-350, -20));
    await tester.pumpAndSettle();
    expect(find.text('3 / $realFrames'), findsOneWidget);
    expect(barShown(tester), isFalse,
        reason: 'наклонный свайп галереи не должен раскрывать шапку');

    // Свайп вправо — к первому кадру.
    await tester.drag(find.byType(PageView), const Offset(350, 0));
    await tester.pumpAndSettle();
    expect(find.text('2 / $realFrames'), findsOneWidget);
    expect(barShown(tester), isFalse,
        reason: 'свайп галереи вправо не должен раскрывать шапку');

    // Быстрый горизонтальный флинг.
    await tester.fling(find.byType(PageView), const Offset(-400, 0), 1000);
    await tester.pumpAndSettle();
    expect(find.text('3 / $realFrames'), findsOneWidget);
    expect(barShown(tester), isFalse,
        reason: 'флинг по галерее не должен раскрывать шапку');

    // Реальная вертикальная прокрутка страницы — шапка раскрывается.
    await tester.drag(find.byType(ListView), const Offset(0, -350));
    await tester.pumpAndSettle();
    expect(barShown(tester), isTrue,
        reason: 'вертикальная прокрутка страницы раскрывает шапку');
  });
}
