// A3 (9-й проход): согласованное поведение остановки плеера.
//
// Уход со страницы точки (назад) НЕ глушит трек, запущенный
// пользователем: мини-плеер подхватывает его на любом экране.
// Остановка — только явная: крестик пилюли, шторка «Сейчас
// играет», закрытие шторки POI на карте.

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

  testWidgets('уход со страницы POI не останавливает трек (A3)',
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

    await tester.runAsync(() async {
      await container.read(poisFamily('gemiler').future);
    });

    rootBundle.clear();

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: PoiDetailPage(
            poiId: 'poi-01',
            islandId: 'gemiler',
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // Запускаем трек со страницы точки (кнопка «Слушать»).
    await tester.tap(find.text('Слушать'));

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(service.isPlaying, isTrue);
    expect(
      service.currentFile,
      'content/fethiye/gemiler/audio/way/poi-01.mp3',
    );

    // Уходим со страницы (назад) — трек продолжает звучать:
    // мини-плеер подхватит его на любом экране (A3).
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: Scaffold(body: SizedBox.shrink()),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(
      service.currentFile,
      'content/fethiye/gemiler/audio/way/poi-01.mp3',
      reason: 'dispose страницы больше не останавливает свой трек',
    );

    expect(service.isPlaying, isTrue,
        reason: 'прослушивание продолжается после ухода со страницы');

    // Явная остановка работает как раньше.
    await tester.runAsync(() async {
      await service.stop();
    });

    expect(service.currentFile, isNull);
  });
}
