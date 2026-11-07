// A11 (17-й проход): ref.watch(poisFamily(...).future) внутри
// async* poiEntryProvider перезапускал весь поток на каждую смену
// состояния зависимости: вотчер создавался заново с пустым
// _inside — пользователь, стоящий в радиусе POI, получал
// ПОВТОРНЫЙ вход (автогид перезапускал/переключал трек) при любом
// invalidate poisFamily.
//
// Теперь внутри потока только ref.read: invalidate семейства не
// трогает живой поток. Проверяем оба инварианта: повторного входа
// нет И поток не перезапускается (checkPermission не вызывается
// заново — признак пересоздания тела провайдера).

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:island_guide/features/audio/providers/auto_audio_provider.dart';
import 'package:island_guide/features/content/models/manifest.dart';
import 'package:island_guide/features/content/providers/content_providers.dart';
import 'package:island_guide/features/gps/models/user_position.dart';
import 'package:island_guide/features/gps/providers/location_providers.dart';
import 'package:island_guide/features/gps/services/location_gateway.dart';
import 'package:island_guide/features/gps/services/location_service.dart';
import 'package:island_guide/features/poi/models/poi.dart';

import 'fakes/fake_location_gateway.dart';

Poi _poi(String id) {
  return Poi(
    id: id,
    title: 'Точка $id',
    latitude: 36.55,
    longitude: 29.07,
    radius: 60,
  );
}

Manifest _manifest(String id, {MapBounds? bounds}) {
  return Manifest(
    id: id,
    name: id,
    version: 1,
    language: 'ru',
    map: '',
    trails: '',
    poi: '',
    audio: '',
    images: '',
    islandBounds: bounds,
  );
}

void main() {
  test('invalidate poisFamily не перезапускает поток и не даёт повторный вход',
      () async {

    final gateway = FakeLocationGateway()
      ..status = LocationPermissionStatus.granted;

    final container = ProviderContainer(
      overrides: [
        locationServiceProvider.overrideWith((ref) {
          final service = LocationService(gateway: gateway);
          ref.onDispose(service.dispose);
          return service;
        }),
        islandsProvider.overrideWith((ref) async => [
              _manifest(
                'gemiler',
                bounds: const MapBounds(
                  west: 29.06,
                  south: 36.54,
                  east: 29.08,
                  north: 36.56,
                ),
              ),
            ]),
        regionsProvider.overrideWith((ref) async => []),
        poisFamily('gemiler').overrideWith(
          (ref) async => [_poi('poi-01')],
        ),
      ],
    );

    addTearDown(container.dispose);

    final events = <PoiEntryEvent>[];

    container.listen(
      poiEntryProvider,
      (_, next) => next.whenData(events.add),
    );

    // Провайдер отработал: подписка на поток живёт.
    await pumpEventQueue();

    // Первый вход в радиус.
    gateway.emit(const UserPosition(latitude: 36.55, longitude: 29.07));

    await pumpEventQueue();

    expect(events, hasLength(1));

    final checkCallsAfterEntry = gateway.checkPermissionCalls;

    // InvalidatepoisFamily: раньше ref.watch перезапускал поток,
    // _inside обнулялся — и следующий тик давал ВТОРОЙ вход.
    container.invalidate(poisFamily('gemiler'));

    await pumpEventQueue();

    // Всё ещё в радиусе — дребезга нет.
    gateway.emit(const UserPosition(latitude: 36.5501, longitude: 29.0701));

    await pumpEventQueue();

    expect(
      events,
      hasLength(1),
      reason: 'invalidate зависимостей не должен обнулять _inside '
          'и повторно запускать гид',
    );

    expect(
      gateway.checkPermissionCalls,
      checkCallsAfterEntry,
      reason: 'тело провайдера НЕ пересоздавалось (иначе был бы '
          'новый checkPermission)',
    );

    await gateway.dispose();
  });
}
