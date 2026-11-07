// Баг 5/D2 (замечания Sonnet): общий хелпер состояния трека
// TrackStateWatcher (файл/playing/позиция/длительность) — им
// пользуются мини-плеер, полоса прогресса и липкая панель POI.
//
// Инварианты: стартовое состояние синхронно, все подписки
// снимаются dispose, смена файла видна потребителю.

import 'package:flutter_test/flutter_test.dart';

import 'package:island_guide/features/audio/presentation/widgets/track_state.dart';
import 'package:island_guide/features/audio/services/audio_player_service.dart';

import 'fakes/fake_audio_gateway.dart';

void main() {
  late FakeAudioGateway gateway;
  late AudioPlayerService service;

  setUp(() {
    gateway = FakeAudioGateway();
    service = AudioPlayerService(gateway: gateway);
  });

  tearDown(() async {
    await service.dispose();
  });

  test('стартовое состояние — синхронно из сервиса (автогид до виджета)',
      () async {
    await service.play('a.mp3');

    var updates = 0;

    final watcher = TrackStateWatcher(
      service: service,
      onUpdate: () => updates++,
    );

    addTearDown(watcher.dispose);

    // Поток не реплеит прошлые события — начальное «играет»
    // виджет обязан увидеть сразу.
    expect(watcher.currentFile, 'a.mp3');
    expect(watcher.playing, isTrue);
    expect(watcher.isLoaded('a.mp3'), isTrue);
    expect(watcher.isLoaded('b.mp3'), isFalse);

    expect(updates, 0);
  });

  test('события стримов приходят колбэком, dispose снимает подписки',
      () async {
    var updates = 0;

    final watcher = TrackStateWatcher(
      service: service,
      onUpdate: () => updates++,
    );

    await service.play('a.mp3');

    gateway.emitDuration(const Duration(minutes: 2));
    gateway.emitPosition(const Duration(seconds: 30));

    await pumpEventQueue();

    expect(updates, greaterThan(0));
    expect(watcher.duration, const Duration(minutes: 2));
    expect(watcher.position, const Duration(seconds: 30));

    // Дослушанный трек — не «играет».
    gateway.emitCompleted();

    await pumpEventQueue();

    expect(watcher.playing, isFalse);

    final updatesBefore = updates;

    watcher.dispose();

    // После dispose события больше не дёргают колбэк и не
    // утекают.
    gateway.emitPosition(const Duration(seconds: 40));

    await pumpEventQueue();

    expect(updates, updatesBefore);
  });

  test('смена файла видна: isLoaded переключается', () async {
    final watcher = TrackStateWatcher(
      service: service,
      onUpdate: () {},
    );

    addTearDown(watcher.dispose);

    await service.play('a.mp3');

    await pumpEventQueue();

    expect(watcher.isLoaded('a.mp3'), isTrue);

    await service.play('b.mp3');

    await pumpEventQueue();

    expect(watcher.currentFile, 'b.mp3');
    expect(watcher.isLoaded('a.mp3'), isFalse);
    expect(watcher.isLoaded('b.mp3'), isTrue);
  });
}
