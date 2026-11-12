// A5 (10-й проход): ошибка продолжения трека с пилюли
// мини-плеера не рвётся необработанным исключением — ловится и
// показывается SnackBar (паттерн mini_player_test для греева
// контента).

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'package:island_guide/features/audio/presentation/widgets/mini_player.dart';
import 'package:island_guide/features/audio/providers/audio_player_provider.dart';
import 'package:island_guide/features/audio/services/audio_player_service.dart';
import 'package:island_guide/features/content/providers/content_providers.dart';

import 'fakes/fake_audio_gateway.dart';
import 'support/test_database.dart';

void main() {
  initTestDatabase();

  testWidgets('ошибка play с пилюли — SnackBar, не крах (A5)',
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

    // Контент Гемилера — в реальной асинхронности (паттерн
    // mini_player_test).
    await tester.runAsync(() async {
      await container.read(regionsProvider.future);
      await container.read(islandsProvider.future);
      await container.read(poisFamily('gemiler').future);
    });

    rootBundle.clear();

    // Трек точки играет: пилюля видна.
    await service.play(
      'content/fethiye/gemiler/audio/way/poi-01.mp3',
    );

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

    expect(find.byIcon(LucideIcons.pause), findsOneWidget);

    // Трек «дослушан» (web-поведение: playing остаётся true при
    // completed) — пилюля показывает «Play»; повторный запуск
    // перезагружает источник (stop + setAsset).
    await tester.runAsync(() async {
      gateway.emitCompleted();

      await Future<void>.delayed(const Duration(milliseconds: 50));
    });

    await tester.pump();
    await tester.pump();

    expect(find.byIcon(LucideIcons.play), findsOneWidget,
        reason: 'дослушанный трек — пилюля предлагает перезапуск');

    // Теперь setAsset падает: перезапуск с пилюли должен
    // обработать ошибку, а не уронить тест необработанным
    // исключением.
    gateway.failSetAsset = true;

    await tester.tap(find.byIcon(LucideIcons.play));

    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });

    await tester.pump();
    await tester.pump();

    expect(
      find.text('Не удалось воспроизвести аудио'),
      findsOneWidget,
      reason: 'ошибка перезапуска показана, трек не потерян молча',
    );

    // Пилюля не «залипла»: трек не играет, иконка «Play».
    expect(find.byIcon(LucideIcons.pause), findsNothing);
  });
}
