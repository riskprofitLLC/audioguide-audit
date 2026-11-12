// A2 (9-й проход): карточка «Продолжить» живо реагирует на
// состояние плеера — play/pause/stop меняют иконку сразу.
//
// Провайдер сервиса отдаёт один объект, watch его не перестраивает:
// раньше иконка оставалась «Play», пока трек уже звучал.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'package:island_guide/features/audio/providers/audio_player_provider.dart';
import 'package:island_guide/features/audio/services/audio_player_service.dart';
import 'package:island_guide/features/content/providers/content_providers.dart';
import 'package:island_guide/features/home/presentation/widgets/continue_card.dart';
import 'package:island_guide/features/poi/models/poi.dart';
import 'package:island_guide/features/settings/services/app_settings.dart';

import 'fakes/fake_audio_gateway.dart';
import 'support/test_database.dart';

void main() {
  initTestDatabase();

  testWidgets('карточка «Продолжить» реагирует на плеер (A2)',
      (tester) async {
    final gateway = FakeAudioGateway();
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

    // Контент — в реальной асинхронности (паттерн AGENTS.md).
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

    expect(find.byKey(const ValueKey('home-continue-card')), findsOneWidget);
    expect(find.text('Вход на остров Гемилер'), findsOneWidget);

    // Тихо — кнопка «Play».
    expect(find.byIcon(LucideIcons.play), findsOneWidget);
    expect(find.byIcon(LucideIcons.pause), findsNothing);

    // Трек зазвучал — карточка перестраивается стримом: «Пауза».
    await tester.runAsync(() async {
      await service.play(
        'content/fethiye/gemiler/audio/way/poi-01.mp3',
      );
    });

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byIcon(LucideIcons.pause), findsOneWidget,
        reason: 'после play карточка обязана показать «Пауза» — '
            'раньше watch синглтона её не перестраивал (A2)');

    // Пауза — обратно «Play».
    await tester.runAsync(() async {
      await service.pause();
    });

    await tester.pump();

    expect(find.byIcon(LucideIcons.play), findsOneWidget);

    // Остановка — карточка остаётся (история никуда не делась),
    // иконка «Play».
    await tester.runAsync(() async {
      await service.stop();
    });

    await tester.pump();

    expect(find.byKey(const ValueKey('home-continue-card')), findsOneWidget);
    expect(find.byIcon(LucideIcons.play), findsOneWidget);
  });

  // Б5 (замечание Sonnet): карточка показывает последний
  // POI С АУДИО — точка без аудио в истории больше не прячет
  // «Продолжить» совсем.
  testWidgets('последний POI без аудио не прячет карточку (Б5)',
      (tester) async {
    final gateway = FakeAudioGateway();

    final service = AudioPlayerService(gateway: gateway);

    // Сервис не диспозим в FakeAsync (как и в тесте A2 выше):
    // await cancel/close подписок broadcast-стрима не завершается
    // без runAsync-зоны.

    // История: свежая точка БЕЗ аудио, старее — с аудио.
    AppSettings().write(
      'recent_items',
      '["poi:gemiler:poi-01","poi:gemiler:poi-02"]',
    );

    final container = ProviderContainer(
      overrides: [
        audioPlayerServiceProvider.overrideWithValue(service),
        currentIslandIdProvider.overrideWith((_) => 'gemiler'),
        // poi-01 — без аудио (id совпадает с первым из истории),
        // poi-02 — с аудио.
        poisFamily('gemiler').overrideWith((ref) async => [
              const Poi(
                id: 'poi-01',
                title: 'Точка без аудио',
                latitude: 36.55,
                longitude: 29.06,
              ),
              const Poi(
                id: 'poi-02',
                title: 'Точка с аудио',
                latitude: 36.56,
                longitude: 29.07,
                audioPath: 'way/poi-02.mp3',
              ),
            ]),
      ],
    );

    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: Scaffold(body: ContinueCard()),
        ),
      ),
    );

    await tester.pump();

    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byKey(const ValueKey('home-continue-card')), findsOneWidget,
        reason: 'точка без аудио в истории не должна прятать карточку');

    expect(
      find.text('Точка с аудио'),
      findsOneWidget,
      reason: 'карточка показывает ближайший по истории POI С аудио',
    );

    expect(find.text('Точка без аудио'), findsNothing);
  });
}
