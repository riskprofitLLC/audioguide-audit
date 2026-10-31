// A5 (10-й проход): ошибка запуска трека с карточки «Продолжить»
// не рвётся необработанным исключением — сервис делает rethrow,
// карточка ловит и показывает SnackBar.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'package:island_guide/features/audio/providers/audio_player_provider.dart';
import 'package:island_guide/features/audio/services/audio_player_service.dart';
import 'package:island_guide/features/content/providers/content_providers.dart';
import 'package:island_guide/features/home/presentation/widgets/continue_card.dart';
import 'package:island_guide/features/settings/services/app_settings.dart';

import 'fakes/fake_audio_gateway.dart';
import 'support/test_database.dart';

void main() {
  initTestDatabase();

  testWidgets('ошибка play в «Продолжить» — SnackBar, не крах (A5)',
      (tester) async {
    final gateway = FakeAudioGateway()..failSetAsset = true;

    final service = AudioPlayerService(gateway: gateway);

    // Последний открытый POI — poi-01 Гемилера (с аудио).
    AppSettings().write(
      'recent_items',
      '["poi:gemiler:poi-01"]',
    );

    final container = ProviderContainer(
      overrides: [
        audioPlayerServiceProvider.overrideWithValue(service),
        currentIslandIdProvider.overrideWith((_) => 'gemiler'),
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
        child: const MaterialApp(
          home: Scaffold(body: ContinueCard()),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.byIcon(LucideIcons.play), findsOneWidget);

    // Тап по Play: setAsset падает — исключение ловится на месте.
    await tester.tap(find.byIcon(LucideIcons.play));

    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });

    await tester.pump();
    await tester.pump();

    expect(
      find.text('Не удалось воспроизвести аудио'),
      findsOneWidget,
      reason: 'ошибка запуска показывается человеку, а не летит '
          'необработанной в зону приложения',
    );

    // Кнопка не «залипла» в состоянии «Пауза» — трек не играет.
    expect(find.byIcon(LucideIcons.pause), findsNothing);
    expect(service.isPlaying, isFalse);

    // Повторный тап — снова ошибка (не разовый сбой), без краха.
    await tester.tap(find.byIcon(LucideIcons.play));

    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });

    await tester.pump();
    await tester.pump();

    expect(find.text('Не удалось воспроизвести аудио'), findsOneWidget);
  });
}
