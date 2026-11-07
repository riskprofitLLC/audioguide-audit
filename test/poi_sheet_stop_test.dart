// A4 (10-й проход): закрытие шторки POI на карте глушит только
// трек ЭТОЙ точки.
//
// Раньше закрытие шторки останавливало ЛЮБОЙ играющий трек:
// автогид или вручную запущенный рассказ другой точки умирал,
// когда пользователь просто заглядывал в карточку и закрывал её.
// Аудиогид — фон путешествия, остановка — только явная.

import 'package:flutter_test/flutter_test.dart';

import 'package:island_guide/features/audio/services/audio_player_service.dart';
import 'package:island_guide/features/map/presentation/widgets/map_widget.dart';
import 'package:island_guide/features/poi/models/poi.dart';

import 'fakes/fake_audio_gateway.dart';

void main() {
  // Точка Гемилера poi-01 (реальный путь аудио из poi.json).
  const poi01 = Poi(
    id: 'poi-01',
    title: 'Вход на остров',
    latitude: 36.55,
    longitude: 29.07,
    audioPath: 'way/poi-01.mp3',
  );

  // Другая точка той же локации.
  const poi02 = Poi(
    id: 'poi-02',
    title: 'Маяк',
    latitude: 36.56,
    longitude: 29.08,
    audioPath: 'way/poi-02.mp3',
  );

  test('играет файл этой точки — остановка нужна', () {
    final current = poi01.audioAssetPath('gemiler');

    expect(shouldStopAfterPoiSheetClose(current, poi01, 'gemiler'), isTrue);
  });

  test('играет чужой файл — трек не трогаем', () {
    final current = poi02.audioAssetPath('gemiler');

    expect(
      shouldStopAfterPoiSheetClose(current, poi01, 'gemiler'),
      isFalse,
      reason: 'закрытие карточки poi-01 не должно глушить трек poi-02',
    );
  });

  test('ничего не играет — остановки нет', () {
    expect(shouldStopAfterPoiSheetClose(null, poi01, 'gemiler'), isFalse);
  });

  test('у точки нет аудио — остановки нет', () {
    const noAudio = Poi(
      id: 'poi-03',
      title: 'Без аудио',
      latitude: 36.57,
      longitude: 29.09,
    );

    expect(
      shouldStopAfterPoiSheetClose('content/fethiye/gemiler/audio/way/poi-01.mp3', noAudio, 'gemiler'),
      isFalse,
    );
  });

  testWidgets('интеграция: чужой трек продолжает играть после решения',
      (tester) async {
    final gateway = FakeAudioGateway();

    final service = AudioPlayerService(gateway: gateway);

    // Играет трек poi-02; пользователь открыл и закрыл карточку
    // poi-01 — решение «не останавливать», сервис не трогаем.
    await service.play(poi02.audioAssetPath('gemiler'));

    expect(service.isPlaying, isTrue);

    final stop = shouldStopAfterPoiSheetClose(
      service.currentFile,
      poi01,
      'gemiler',
    );

    expect(stop, isFalse,
        reason: 'шторка poi-01 закрыта, играет poi-02 — фон живёт');

    // Контроль: своя точка — решение «остановить», stop() глушит.
    expect(
      shouldStopAfterPoiSheetClose(service.currentFile, poi02, 'gemiler'),
      isTrue,
    );

    await service.stop();

    expect(service.isPlaying, isFalse);
  });
}
