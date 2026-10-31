// Тест мини-плеера (A2): пилюля видна, пока трек играет вне
// страницы своего POI, и скрывается, когда открыта модальная
// шторка (modalSheetOpenCount, A2b).

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'package:island_guide/app/overlay_tracker.dart';
import 'package:island_guide/features/audio/presentation/widgets/mini_player.dart';
import 'package:island_guide/features/audio/providers/audio_player_provider.dart';
import 'package:island_guide/features/audio/services/audio_player_service.dart';
import 'package:island_guide/features/content/providers/content_providers.dart';

import 'fakes/fake_audio_gateway.dart';
import 'support/test_database.dart';

void main() {
  initTestDatabase();

  testWidgets(
    'мини-плеер прячется под модальной шторкой и возвращается',
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

      // Контент Гемилера (~55 КБ) грузим в runAsync — паттерн
      // tree_navigation_test: пилюля резолвит POI по кешу
      // провайдеров.
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
          child: const MaterialApp(
            home: Scaffold(
              body: Stack(
                children: [
                  SizedBox.expand(),
                  MiniPlayerOverlay(),
                ],
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Пилюля на экране (трек играет вне страницы своего POI).
      expect(find.byIcon(LucideIcons.audioLines), findsOneWidget);

      // Открылась модальная шторка — пилюля скрылась (A2b).
      modalSheetOpenCount.value++;

      await tester.pump();

      expect(find.byIcon(LucideIcons.audioLines), findsNothing);

      // Шторка закрылась — пилюля вернулась.
      modalSheetOpenCount.value--;

      await tester.pump();

      expect(find.byIcon(LucideIcons.audioLines), findsOneWidget);

      // Пауза с пилюли НЕ прячет её (A3, 9-й проход): трек,
      // отпущенный со страницы точки, обязан оставаться
      // доступным — иконка меняется на «Play».
      await tester.runAsync(() async {
        await service.pause();

        // Очередь операций сервиса живёт в реальной зоне —
        // даём микротаскам отработать до возврата в FakeAsync.
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });

      await tester.pump();
      await tester.pump();

      expect(find.byIcon(LucideIcons.audioLines), findsOneWidget,
          reason: 'пауза не должна терять трек вне страницы точки');

      expect(find.byIcon(LucideIcons.play), findsOneWidget);
      expect(find.byIcon(LucideIcons.pause), findsNothing);

      // Продолжение с той же пилюли: хвост очереди сервиса —
      // реальная зона, поэтому флашим её runAsync'ом.
      await tester.tap(find.byIcon(LucideIcons.play));

      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });

      await tester.pump();
      await tester.pump();

      expect(find.byIcon(LucideIcons.pause), findsOneWidget);

      // Трек остановлен — пилюля исчезает.
      await tester.runAsync(() async {
        await service.stop();
      });

      await tester.pump();

      expect(find.byIcon(LucideIcons.audioLines), findsNothing);
    },
  );
}
