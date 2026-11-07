// Мини-плеер (P0-5, 6-й проход):
// 1. «Своя» страница POI сверяется по пути И локации — id точек
//    повторяются между локациями, на /poi/poi-01?island=bay при
//    играющем gemiler/poi-01 пилюля раньше пряталась зря.
// 2. POI резолвится по ПОДПИСКЕ на провайдер: пока данные
//    локации не загружены, ref.read молчал до первого стороннего
//    rebuild — пилюля не появлялась после загрузки.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'package:island_guide/features/audio/presentation/widgets/mini_player.dart';
import 'package:island_guide/features/audio/providers/audio_player_provider.dart';
import 'package:island_guide/features/audio/services/audio_player_service.dart';
import 'package:island_guide/features/content/providers/content_providers.dart';
import 'package:island_guide/features/poi/models/poi.dart';

import 'fakes/fake_audio_gateway.dart';
import 'support/test_database.dart';

void main() {
  initTestDatabase();

  group('isOnOwnPoiPage', () {
    test('путь и локация совпадают — своя страница', () {
      expect(
        isOnOwnPoiPage(
          Uri.parse('/poi/poi-01?island=gemiler'),
          poiId: 'poi-01',
          locationId: 'gemiler',
          fallbackIslandId: 'bay',
        ),
        isTrue,
      );
    });

    test('тот же id в ДРУГОЙ локации — не своя страница', () {
      expect(
        isOnOwnPoiPage(
          Uri.parse('/poi/poi-01?island=bay'),
          poiId: 'poi-01',
          locationId: 'gemiler',
          fallbackIslandId: 'gemiler',
        ),
        isFalse,
        reason: 'id POI повторяются между локациями: играющий '
            'gemiler/poi-01 не должен прятать пилюлю на странице '
            'bay/poi-01',
      );
    });

    test('другой id в той же локации — не своя страница', () {
      expect(
        isOnOwnPoiPage(
          Uri.parse('/poi/poi-02?island=gemiler'),
          poiId: 'poi-01',
          locationId: 'gemiler',
          fallbackIslandId: 'gemiler',
        ),
        isFalse,
      );
    });

    test('адрес без island — сверка с текущей локацией приложения', () {
      // PoiDetailPage без ?island= показывает текущую локацию.
      expect(
        isOnOwnPoiPage(
          Uri.parse('/poi/poi-01'),
          poiId: 'poi-01',
          locationId: 'gemiler',
          fallbackIslandId: 'gemiler',
        ),
        isTrue,
      );

      expect(
        isOnOwnPoiPage(
          Uri.parse('/poi/poi-01'),
          poiId: 'poi-01',
          locationId: 'gemiler',
          fallbackIslandId: 'bay',
        ),
        isFalse,
      );
    });

    test('не страница POI — не своя', () {
      expect(
        isOnOwnPoiPage(
          Uri.parse('/map?search=1'),
          poiId: 'poi-01',
          locationId: 'gemiler',
          fallbackIslandId: 'gemiler',
        ),
        isFalse,
      );
    });
  });

  testWidgets('пилюля появляется, когда данные локации догрузились',
      (tester) async {
    final service = AudioPlayerService(gateway: FakeAudioGateway());

    // Загрузку POI контролируем из теста: complete-лак postponed
    // до момента, когда пилюля уже построена (провайдер реального
    // контента стартует в FakeAsync-зоне и висит — см. AGENTS.md).
    final poiList = Completer<List<Poi>>();

    final container = ProviderContainer(
      overrides: [
        audioPlayerServiceProvider.overrideWithValue(service),
        currentIslandIdProvider.overrideWith((_) => 'gemiler'),
        poisFamily('gemiler').overrideWith((ref) => poiList.future),
      ],
    );

    addTearDown(container.dispose);

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

    await tester.pump();

    // Раньше ref.read(poisFamily(...)).value молчал навсегда:
    // без подписки загрузка провайдера не перестраивала пилюлю.
    expect(find.byIcon(LucideIcons.audioLines), findsNothing,
        reason: 'POI играющего трека ещё не загружен');

    // Данные локации догрузились — пилюля появляется без
    // стороннего rebuild.
    poiList.complete([
      const Poi(
        id: 'poi-01',
        title: 'Церковь на острове',
        latitude: 36.6,
        longitude: 29.07,
        audioPath: 'way/poi-01.mp3',
      ),
    ]);

    await tester.pump();
    await tester.pump();

    expect(find.byIcon(LucideIcons.audioLines), findsOneWidget,
        reason: 'после загрузки данных локации пилюля появляется');

    expect(find.text('Церковь на острове'), findsOneWidget);
  });
}
