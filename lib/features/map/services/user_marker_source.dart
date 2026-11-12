import '../../../core/utils/logger.dart';
import '../../gps/models/user_position.dart';

/// Приёмник GeoJSON-обновлений маркера пользователя (узкий
/// интерфейс над контроллером карты — ради фейка в тестах).
abstract interface class UserMarkerSink {

  /// Полная замена GeoJSON источника карты.
  Future<void> setGeoJsonSource(String sourceId, Map<String, Object?> data);
}

/// Состояние маркера «Вы здесь» (A1/A2, 17-й проход).
///
/// Решает две проблемы пересборки оверлеев:
///
/// - помнит последнюю позицию — после пересборки (смена локации,
///   перезагрузка стиля, смена режима «все регионы» ↔ локация)
///   маркер восстанавливается СРАЗУ, а не с ближайшего GPS-тика:
///   при `distanceFilter: 10` стоящий на месте пользователь не
///   получил бы точку назад, пока не сдвинется на 10 м;
/// - «не готов» после удаления слоя: позиции, пришедшие во время
///   пересборки, НЕ пишутся в несуществующий источник
///   (unhandled PlatformException) — только запоминаются.
///
/// B1 (18-й проход): фича несёт свойство `fresh` — «свежий/давний»
/// фикс; устаревшая точка рисуется приглушённой, круг точности и
/// конус курса на ней скрыты (выражения слоёв в map_overlays.dart).
final class UserMarkerSource {

  /// Идентификатор источника карты (общая константа виджета).
  static const sourceId = 'user-position';

  bool _ready = false;

  UserPosition? _last;

  /// Последняя известная позиция (восстанавливается при пересборке).
  UserPosition? get last => _last;


  /// Слой пользователя добавлен на карту — можно писать GeoJSON.
  void onLayerAdded() {
    _ready = true;
  }


  /// Слой удалён (пересборка оверлеев): источник исчез — писаем
  /// только после нового добавления.
  void onLayerRemoved() {
    _ready = false;
  }


  /// Запоминает позицию БЕЗ записи в слой (A9, 18-й проход):
  /// карта ещё не построена — фикс не должен потеряться до
  /// первого добавления слоя (восстановится через restoreInto).
  void remember(UserPosition position) {
    _last = position;
  }


  /// Новая позиция: запоминается ВСЕГДА, пишется только в
  /// готовый слой; ошибки платформы не роняют тик GPS.
  ///
  /// [fresh] — состояние «свежести» фикса (B1): приглушённая
  /// точка у давнего фикса.
  Future<void> update(
    UserPosition position,
    UserMarkerSink sink, {
    bool fresh = true,
  }) async {

    _last = position;

    await write(position, sink, fresh: fresh);
  }


  /// Пишет позицию в слой, НЕ трогая запомненную [_last]:
  /// так интерполяция маркера (B2, 18-й проход) рисует
  /// промежуточные кадры, не подменяя реальный фикс.
  Future<void> write(
    UserPosition position,
    UserMarkerSink sink, {
    bool fresh = true,
  }) async {

    if (!_ready) {
      return;
    }

    try {

      await sink.setGeoJsonSource(
        sourceId,
        featureCollection(position, fresh: fresh),
      );

    } catch (error) {

      AppLogger.warning(
        '[UserMarkerSource] setGeoJsonSource failed: $error',
      );
    }
  }


  /// Восстанавливает маркер после пересборки оверлеев (A1):
  /// своя последняя позиция или свежая из сервиса (`fallback`).
  ///
  /// [fallbackFresh] — состояние «свежести» позиций-фолбэков:
  /// платформенный last-known (B1) показывается приглушённым.
  Future<void> restoreInto(
    UserMarkerSink sink, {
    UserPosition? fallback,
    bool fallbackFresh = true,
  }) async {

    final position = _last ?? fallback;

    if (position == null) {
      return;
    }

    // Свой `_last` — живой фикс (fresh); фолбэк — по параметру.
    final fresh = _last != null ? true : fallbackFresh;

    _ready = true;

    try {

      await sink.setGeoJsonSource(
        sourceId,
        featureCollection(position, fresh: fresh),
      );

    } catch (error) {

      AppLogger.warning(
        '[UserMarkerSource] restore failed: $error',
      );
    }
  }


  /// GeoJSON-пакет позиции для источника user-position.
  ///
  /// Свойства:
  /// - `fresh` — «свежесть» фикса (B1): устаревшая точка
  ///   приглушается выражениями слоёв;
  /// - `lat` + `accuracy` — круг точности (радиус в метрах
  ///   пересчитывается в пиксели zoom-выражением слоя);
  /// - `heading` + `speed` — конус направления (только при
  ///   движении).
  ///
  /// A7 (18-й проход): `null`-свойства НЕ пишутся — фильтры
  /// `has`/`>` по null-ключам на web вычислялись с ошибкой
  /// (круг точности с радиусом NaN, стрелка не появлялась).
  /// `null`-позиция — пустая коллекция (слой ничего не рисует).
  static Map<String, Object?> featureCollection(
    UserPosition? position, {
    bool fresh = true,
  }) {

    if (position == null) {
      return const {
        'type': 'FeatureCollection',
        'features': <Map<String, Object?>>[],
      };
    }

    return {
      'type': 'FeatureCollection',
      'features': [
        {
          'type': 'Feature',
          'properties': <String, Object?>{
            'fresh': fresh,
            'lat': position.latitude,
            if (position.accuracy != null) 'accuracy': position.accuracy,
            if (position.speed != null) 'speed': position.speed,
            if (position.heading != null) 'heading': position.heading,
          },
          'geometry': {
            'type': 'Point',
            'coordinates': [
              position.longitude,
              position.latitude,
            ],
          },
        },
      ],
    };
  }


  /// Линейная интерполяция позиции (B2, 18-й проход): маркер
  /// едет между фиксами, а не прыгает.
  ///
  /// Точность/курс/скорость берутся от целевого фикса (куда едем);
  /// метка времени — от целевого (это «его» кадр).
  static UserPosition lerp(
    UserPosition from,
    UserPosition to,
    double t,
  ) {

    final clamped = t.clamp(0.0, 1.0);

    return UserPosition(
      latitude: from.latitude + (to.latitude - from.latitude) * clamped,
      longitude: from.longitude + (to.longitude - from.longitude) * clamped,
      accuracy: to.accuracy,
      speed: to.speed,
      heading: to.heading,
      timestamp: to.timestamp,
    );
  }
}
