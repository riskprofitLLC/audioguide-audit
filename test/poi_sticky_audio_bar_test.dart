// D3 (замечания Sonnet): липкая панель аудио страницы POI.
//
// Плеер статьи ушёл за верх — управление остаётся под пальцем.
// Отдельный файл: один контент-тест на файл (rootBundle под
// FakeAsync, см. AGENTS.md).

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'package:island_guide/features/audio/providers/audio_player_provider.dart';
import 'package:island_guide/features/audio/services/audio_player_service.dart';
import 'package:island_guide/features/content/providers/content_providers.dart';
import 'package:island_guide/features/poi/presentation/pages/poi_detail_page.dart';

import 'fakes/fake_audio_gateway.dart';
import 'support/test_database.dart';

void main() {
  initTestDatabase();

  testWidgets(
    'липкая панель: появляется при прокрутке плеера за верх, '
    'без переполнений на 360×640 / textScale 1.6 (D3)',
    (tester) async {
      tester.view
        ..physicalSize = const Size(360, 640)
        ..devicePixelRatio = 1.0;

      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final gateway = FakeAudioGateway();
      final service = AudioPlayerService(gateway: gateway);

      final container = ProviderContainer(
        overrides: [
          audioPlayerServiceProvider.overrideWithValue(service),
        ],
      );

      addTearDown(container.dispose);

      await tester.runAsync(() async {
        await container.read(poisFamily('gemiler').future);
      });

      rootBundle.clear();

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            // copyWith поверх ЖИВОГО MediaQuery: пустой MediaQueryData
            // обнуляет size/dpr для всего дерева (cacheWidth==0).
            home: Builder(
              builder: (context) => MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  textScaler: const TextScaler.linear(1.6),
                ),
                child: const PoiDetailPage(
                  poiId: 'poi-11',
                  islandId: 'gemiler',
                ),
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Пока плеер статьи на экране — панели нет.
      expect(find.byKey(const ValueKey('poi-sticky-audio')), findsNothing);

      // Трек ЭТОЙ точки играет с самого старта (как автогид до
      // открытия страницы) — панель обязана управлять им.
      await service.play(
        'content/fethiye/gemiler/audio/no-way/poi-11.mp3',
      );

      await tester.pumpAndSettle();

      // Панель ещё не нужна: плеер статьи в кадре.
      expect(find.byKey(const ValueKey('poi-sticky-audio')), findsNothing);

      // Плеер ушёл за верх — панель появляется. Страница при
      // textScale 1.6 длинная: скроллим порциями до результата.
      var appeared = false;

      for (var i = 0; i < 12 && !appeared; i++) {
        await tester.drag(
          find.byType(ListView),
          const Offset(0, -300),
        );

        await tester.pumpAndSettle();

        appeared =
            find.byKey(const ValueKey('poi-sticky-audio')).evaluate().isNotEmpty;
      }

      expect(
        appeared,
        isTrue,
        reason: 'панель аудио видна при прокрученном плеере',
      );

      // Переполнений нет (RenderFlex overflow роняет матрицу).
      expect(tester.takeException(), isNull);

      // Панель управляет треком этой точки (баг 5: подписана на
      // файл — тумблер показывает «Пауза»).
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('poi-sticky-audio')),
          matching: find.byIcon(LucideIcons.pause),
        ),
        findsOneWidget,
      );
    },
  );
}
