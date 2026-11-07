import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/logger.dart';
import '../../content/models/manifest.dart';
import '../../content/models/region_catalog.dart';
import '../../content/providers/content_providers.dart';
import '../../gps/providers/location_providers.dart';
import '../../gps/services/location_gateway.dart';
import '../../gps/services/location_service.dart';
import '../../gps/services/poi_proximity_watcher.dart';
import '../../poi/models/poi.dart';
import 'audio_player_provider.dart';


/// Событие автогида: пользователь вошёл в радиус POI.
///
/// Локация передаётся ВМЕСТЕ с POI: событие относится к точке
/// конкретной локации, а текущая выбранная локация могла уже
/// смениться (автогид ловит и соседние локации, A3).
typedef PoiEntryEvent = ({String islandId, Poi poi});


/// Радиус подбора локаций-кандидатов вокруг позиции (метры).
///
/// Больше максимального радиуса POI (60 м) с запасом на скорость
/// пешего/плавного перемещения между тиками GPS: локации рядом с
/// пользователем подгружаются заранее, дальние не будятся вовсе.
const double _nearbyLocationsRadius = 3000;

/// Локации-кандидаты автогида: точки, в радиус которых пользователь
/// может войти в ближайшие минуты.
///
/// Границы — манифестные `islandBounds` локации (bbox её POI,
/// `tool/patch_location_bounds.py`); если у локации их нет —
/// грубые `mapBounds` региона. Локации без каких-либо границ не
/// участвуют (их контент не подгрузить заранее, а угадывать
/// «везде» — значит будить сидинг всех пакетов).
List<String> nearbyLocationIds({
  required List<Manifest> locationManifests,
  required Map<String, Manifest> regionManifests,
  required double latitude,
  required double longitude,
  double radiusMeters = _nearbyLocationsRadius,
}) {
  final result = <String>[];

  for (final manifest in locationManifests) {
    MapBounds? bounds = manifest.islandBounds;

    if (bounds == null) {
      final regionId = regionOfLocation(manifest.id).id;

      bounds = regionManifests[regionId]?.mapBounds;
    }

    if (bounds == null) {
      continue;
    }

    if (LocationService.distanceToBoundsMeters(latitude, longitude, bounds) <=
        radiusMeters) {
      result.add(manifest.id);
    }
  }

  return result;
}


/// Поток событий «пользователь вошёл в радиус POI».
///
/// На каждое событие голосовой гид запускается автоматически
/// (см. MapPage — слушатель живёт на экране карты).
///
/// Провайдер autoDispose: GPS-поток и разрешение геолокации не
/// запрашиваются с запуска приложения, а только пока открыт экран
/// карты (осознанное действие пользователя). Когда карта закрыта —
/// подписка отменяется, LocationService останавливает GPS.
///
/// A3, 8-й проход: вотчер следит за точками ВСЕХ локаций в ~3 км
/// от пользователя (не только текущей выбранной). Раньше гид молчал
/// у точки соседней локации, пока пользователь вручную не переключит
/// её. Локации-кандидаты выбираются по манифестным bounds, их POI
/// подгружаются лениво и кешируются в `poisFamily` — холодного
/// сидинга всех 9 пакетов не происходит.
final poiEntryProvider =
    StreamProvider.autoDispose<PoiEntryEvent>((ref) async* {

  AppLogger.info('[poiEntryProvider] starting (multi-location)');

  final location =
      ref.watch(locationServiceProvider);

  // Мягкий запрос (P1-1, 7-й проход): разрешение только
  // проверяется, без системного диалога. Автогид включается
  // после явного разрешения пользователя (плашка «Включить
  // геолокацию» / кнопка GPS на карте).
  final status = await location.checkPermission();

  AppLogger.info('[poiEntryProvider] permission=$status');

  if (status != LocationPermissionStatus.granted) {

    return;
  }

  // Манифесты — лёгкие (по одному на регион/локацию), для
  // гео-выбора кандидатов они нужны целиком.
  //
  // A11 (17-й проход): внутри async* после await — ТОЛЬКО
  // ref.read. ref.watch перезапускал весь поток на каждую смену
  // состояния зависимости (invalidate poisFamily после сидинга
  // обновлений, пересев): вотчер создавался заново с пустым
  // _inside, и стоящий в радиусе пользователь получал
  // ПОВТОРНЫЙ вход — автогид перезапускал/переключал трек.
  // Манифесты и точки загружаются один раз — обновления контента
  // подхватит следующий запуск провайдера (переоткрытие карты).
  final locationManifests =
      await ref.read(islandsProvider.future);

  final regionManifests = {
    for (final manifest in await ref.read(regionsProvider.future))
      manifest.id: manifest,
  };

  final watcher = MultiLocationPoiWatcher();

  /// Локации, чьи POI уже в вотчере.
  final loaded = <String>{};

  /// Локации, чья загрузка упала — не дёргаем их на каждом тике.
  final failed = <String>{};

  await for (final position in location.positions) {

    final candidates = nearbyLocationIds(
      locationManifests: locationManifests,
      regionManifests: regionManifests,
      latitude: position.latitude,
      longitude: position.longitude,
    );

    for (final candidate in candidates) {
      if (loaded.contains(candidate) || failed.contains(candidate)) {
        continue;
      }

      try {
        final pois =
            await ref.read(poisFamily(candidate).future);

        watcher.add(candidate, pois);

        loaded.add(candidate);

        AppLogger.info(
          '[poiEntryProvider] island=$candidate loaded '
          '(${pois.length} pois), watching proximity',
        );
      } catch (error) {
        failed.add(candidate);

        AppLogger.error(
          '[poiEntryProvider] island=$candidate load failed',
          error: error,
        );
      }
    }

    for (final entry in watcher.update(position)) {

      AppLogger.info('[poiEntryProvider] ENTER radius '
          '${entry.$1}/${entry.$2.id} ${entry.$2.title}');

      yield (islandId: entry.$1, poi: entry.$2);
    }
  }
});


/// Запускает голосовой гид для POI.
///
/// Использует общий плеер приложения — он сам защищает
/// от повторного запуска уже звучащего файла.
Future<void> playPoiAudio(
  WidgetRef ref, {
  required Poi poi,
  required String islandId,
}) async {

  final audioPath = poi.audioPath;

  if (audioPath == null) {

    return;
  }

  final audioService =
      ref.read(audioPlayerServiceProvider);

  try {
    await audioService.play(
      poi.audioAssetPath(islandId),
    );

  } catch (error) {

    // Например, автоплей-политика браузера на web:
    // аудио не может стартовать без жеста пользователя.
    AppLogger.error(
      'Не удалось запустить автоаудиогид ${poi.id}',
      error: error,
    );
  }
}
