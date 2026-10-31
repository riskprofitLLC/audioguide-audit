// Тест плеера голосового гида на странице POI.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'package:island_guide/features/audio/presentation/widgets/audio_guide_player.dart';
import 'package:island_guide/features/audio/providers/audio_player_provider.dart';
import 'package:island_guide/features/audio/services/audio_player_service.dart';
import 'package:island_guide/features/content/providers/content_providers.dart';
import 'package:island_guide/features/poi/presentation/pages/poi_detail_page.dart';

import 'fakes/fake_audio_gateway.dart';
import 'support/test_database.dart';

void main() {

  initTestDatabase();

  testWidgets('POI-страница показывает дорожку и запускает плеер по кнопке',
      (tester) async {
    final gateway = FakeAudioGateway();
    final service = AudioPlayerService(gateway: gateway);

    // poi.json Гемилера (~55 КБ) не грузится под FakeAsync (порог
    // ~50 КБ, см. AGENTS.md) — контент сеем в runAsync и читаем из
    // кеша провайдеров (паттерн tree_navigation_test).
    final container = ProviderContainer(
      overrides: [
        audioPlayerServiceProvider.overrideWithValue(service),
      ],
    );

    addTearDown(container.dispose);

    await tester.runAsync(() async {
      await container.read(poisFamily('gemiler').future);
    });

    // Будущие ассетов, созданные в зоне runAsync, под FakeAsync не
    // завершаются (колбэки .then идут в зону создания Future).
    // Чистим кеш — холодные дочитывания пойдут уже в зоне теста.
    rootBundle.clear();

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: PoiDetailPage(
            poiId: 'poi-11',
            islandId: 'gemiler',
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Причал острова Гемилер'), findsOneWidget);

    // Ряд действий (B3.3): главный «Слушать» — primary.
    expect(find.text('Слушать'), findsOneWidget);
    expect(find.text('На карте'), findsOneWidget);

    // Плеер ниже по списку (после фото, заголовка, карты и текста) —
    // прокручиваем к нему.
    await tester.drag(
      find.byType(ListView),
      const Offset(0, -400),
    );
    await tester.pumpAndSettle();

    // Дорожка видна сразу, воспроизведение ещё не началось.
    // Файл предзагружен, чтобы была видна длительность.
    expect(find.text('Аудиогид'), findsOneWidget);

    // Play только в плеере: «Слушать» из ряда действий — свой
    // экземпляр иконки (B3.3).
    final playerPlay = find.descendant(
      of: find.byType(AudioGuidePlayer),
      matching: find.byIcon(LucideIcons.play),
    );

    expect(playerPlay, findsOneWidget);
    expect(gateway.loaded, contains('content/fethiye/gemiler/audio/no-way/poi-11.mp3'));
    expect(service.isPlaying, isFalse);

    // Нажатие на Play запускает файл.
    await tester.tap(playerPlay);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(gateway.loaded, ['content/fethiye/gemiler/audio/no-way/poi-11.mp3']);
    expect(service.isPlaying, isTrue);

    final playerPause = find.descendant(
      of: find.byType(AudioGuidePlayer),
      matching: find.byIcon(LucideIcons.pause),
    );

    expect(playerPause, findsOneWidget);

    // Повторное нажатие ставит на паузу.
    await tester.tap(playerPause);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(service.isPlaying, isFalse);
    expect(playerPlay, findsOneWidget);
  });
}
