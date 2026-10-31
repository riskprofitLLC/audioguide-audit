// A3 (10-й проход): полноэкранный просмотр фото и сетка «Все
// фото» регистрируются в modalSheetOpenCount — пилюля
// мини-плеера живёт НАД Navigator'ом и без регистрации рисовалась
// поверх чёрного просмотра (перекрывала счётчик и атрибуцию).

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'package:island_guide/app/overlay_tracker.dart';
import 'package:island_guide/features/audio/presentation/widgets/mini_player.dart';
import 'package:island_guide/features/audio/providers/audio_player_provider.dart';
import 'package:island_guide/features/audio/services/audio_player_service.dart';
import 'package:island_guide/features/content/presentation/widgets/image_gallery.dart';
import 'package:island_guide/features/content/providers/content_providers.dart';

import 'fakes/fake_audio_gateway.dart';
import 'support/test_database.dart';

void main() {
  initTestDatabase();

  testWidgets(
    'пилюля скрыта под полноэкранной галереей и сеткой фото (A3)',
    (tester) async {
      final gateway = FakeAudioGateway();

      final service = AudioPlayerService(gateway: gateway);

      final container = ProviderContainer(
        overrides: [
          audioPlayerServiceProvider.overrideWithValue(service),
          currentIslandIdProvider.overrideWith((_) => 'gemiler'),
        ],
      );

      addTearDown(container.dispose);

      addTearDown(() => modalSheetOpenCount.value = 0);

      // Контент Гемилера — в реальной асинхронности (паттерн
      // mini_player_test): пилюля резолвит POI по кешу.
      await tester.runAsync(() async {
        await container.read(regionsProvider.future);
        await container.read(islandsProvider.future);
        await container.read(poisFamily('gemiler').future);
      });

      rootBundle.clear();

      // Трек точки играет: путь ассета — реальный путь POI.
      await service.play(
        'content/fethiye/gemiler/audio/way/poi-01.mp3',
      );

      expect(service.currentFile, isNotNull);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(
              body: Stack(
                children: [
                  SizedBox.expand(
                    child: Builder(
                      builder: (context) => Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          TextButton(
                            onPressed: () => showFullscreenGallery(
                              context,
                              imagePaths: const ['poi-01/1.jpg'],
                              islandId: 'gemiler',
                            ),
                            child: const Text('fullscreen'),
                          ),
                          TextButton(
                            onPressed: () => showPhotoGridSheet(
                              context,
                              imagePaths: const ['poi-01/1.jpg'],
                              islandId: 'gemiler',
                            ),
                            child: const Text('grid'),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const MiniPlayerOverlay(),
                ],
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Пилюля на экране — трек играет вне страницы своего POI.
      expect(find.byIcon(LucideIcons.audioLines), findsOneWidget);

      // B1 (10-й проход): кнопки пилюли — тап-цель 44 (было 40).
      final pillButtons = tester.widgetList<IconButton>(
        find.byType(IconButton),
      );

      expect(pillButtons, isNotEmpty);

      for (final button in pillButtons) {
        final rect = tester.getRect(find.byWidget(button));

        expect(
          rect.height,
          greaterThanOrEqualTo(44),
          reason: 'кнопки мини-плеера — тап-цель не ниже 44',
        );
      }

      // --- Полноэкранный просмотр: пилюля скрыта.
      await tester.tap(find.text('fullscreen'));
      await tester.pumpAndSettle();

      expect(find.byTooltip('Закрыть просмотр'), findsOneWidget);

      expect(
        find.byIcon(LucideIcons.audioLines),
        findsNothing,
        reason: 'пилюля не рисуется поверх полноэкранного просмотра (A3)',
      );

      // Закрытие просмотра — пилюля вернулась.
      await tester.tap(find.byTooltip('Закрыть просмотр'));
      await tester.pumpAndSettle();

      expect(find.byIcon(LucideIcons.audioLines), findsOneWidget);

      // --- Сетка «Все фото»: пилюля тоже скрыта.
      await tester.tap(find.text('grid'));
      await tester.pumpAndSettle();

      expect(find.text('Все фото (1)'), findsOneWidget);

      expect(
        find.byIcon(LucideIcons.audioLines),
        findsNothing,
        reason: 'пилюля не рисуется поверх сетки «Все фото» (A3)',
      );

      // Закрытие сетки — пилюля вернулась, счётчик в нуле.
      await tester.tap(find.byTooltip('Закрыть'));
      await tester.pumpAndSettle();

      expect(find.byIcon(LucideIcons.audioLines), findsOneWidget);
      expect(modalSheetOpenCount.value, 0);
    },
  );
}
