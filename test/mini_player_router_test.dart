// Б1 (замечание Sonnet): тап по пилюле мини-плеера открывает
// шторку «Сейчас играет». Пилюля живёт в MaterialApp.builder
// НАД Navigator'ом роутера: раньше showModalBottomSheet падал
// «Navigator operation requested with a context that does not
// include a Navigator», а modalSheetOpenCount оставался
// поднятым навсегда — пилюля пряталась до перезапуска.
//
// Проверяется на MaterialApp.router (как в app.dart): шторка
// открывается, счётчик сбрасывается при закрытии.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:island_guide/app/overlay_tracker.dart';
import 'package:island_guide/app/router.dart';
import 'package:island_guide/features/audio/presentation/widgets/mini_player.dart';
import 'package:island_guide/features/audio/providers/audio_player_provider.dart';
import 'package:island_guide/features/audio/services/audio_player_service.dart';
import 'package:island_guide/features/content/providers/content_providers.dart';

import 'fakes/fake_audio_gateway.dart';
import 'support/test_database.dart';

void main() {
  initTestDatabase();

  testWidgets('тап по пилюле открывает «Сейчас играет» через root-навигатор',
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

    // Контент Гемилера — в реальной зоне (паттерн AGENTS.md);
    // play — вне runAsync + флаш (паттерн mini_player_test:
    // сервисная очередь в реальной зоне не завершает runAsync).
    await tester.runAsync(() async {
      await container.read(regionsProvider.future);
      await container.read(islandsProvider.future);
      await container.read(poisFamily('gemiler').future);
    });

    await service.play(
      'content/fethiye/gemiler/audio/way/poi-01.mp3',
    );

    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });


    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(
          routerConfig: AppRouter.router,
          builder: (context, child) => Stack(
            children: [
              Positioned.fill(child: child!),
              const MiniPlayerOverlay(),
            ],
          ),
        ),
      ),
    );

    // Сплэш 900 мс → /home.
    await tester.pump(const Duration(milliseconds: 1000));

    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('mini-player-pill')),
      findsOneWidget,
      reason: 'трек играет вне страницы своего POI — пилюля видна',
    );

    // Тап по пилюле: раньше здесь летело исключение «context that
    // does not include a Navigator» и счётчик шторок навсегда
    // оставался поднятым.
    await tester.tap(find.byKey(const ValueKey('mini-player-pill')));

    await tester.pumpAndSettle();

    expect(find.text('Сейчас играет'), findsOneWidget,
        reason: 'шторка открылась через контекст root-навигатора');

    expect(modalSheetOpenCount.value, 1);

    // Закрываем шторку — счётчик возвращается в ноль, пилюля
    // возвращается.
    await tester.tap(find.byTooltip('Закрыть'));

    await tester.pumpAndSettle();

    expect(modalSheetOpenCount.value, 0,
        reason: 'закрытие шторки обязано откатить счётчик');

    expect(
      find.byKey(const ValueKey('mini-player-pill')),
      findsOneWidget,
      reason: 'пилюля вернулась после закрытия шторки',
    );
  });
}
