import 'dart:math';

import '../../poi/models/poi.dart';
import '../models/user_position.dart';
import 'location_service.dart';

/// POI с локацией, к которой он принадлежит.
///
/// id POI повторяются между локациями (poi-01 в каждой), поэтому
/// внемаршрутный автогид (A3, 8-й проход) различает точки по
/// составному ключу «локация/poi».
typedef LocatedPoi = (String islandId, Poi poi);

/// Порог точности для входа в радиус (A8, 17-й проход), метры.
///
/// Фиксы грубее — игнорируются при входе: на web (WiFi/вышки)
/// точность бывает сотни метров, и «вход в радиус 60 м» при
/// точности 800 м — лотерея с автозапуском чужого рассказа.
/// Выход при этом считается по обычным правилам: точка, в
/// которую уже вошли, не «зависает» навсегда.
const double _maxEntryAccuracy = 100;

/// Гистерезис выхода из радиуса (A8, 17-й проход), метры.
///
/// Раньше фиксированные +10 м: шум GPS ±10–30 м дребезжал точку
/// на границе — рассказ перезапускался. Теперь запас
/// пропорционален радиусу (четверть) и учитывает точность
/// последнего фикса: выход засчитывается, когда пользователь
/// ушёл ЗА радиус на заметное расстояние.
double exitHysteresis(double radius, double? accuracy) {

  final byRadius = max(10.0, radius * 0.25);

  return max(byRadius, accuracy ?? 0.0);
}

/// Следит за позицией пользователя и определяет
/// момент входа в радиус голосового гида POI.
///
/// Чистая логика без зависимостей от Flutter — легко
/// тестируется. Защита от повторного срабатывания:
/// событие входа генерируется только после того, как
/// пользователь покинул радиус точки.
///
/// D2 (замечания Sonnet): тонкая обёртка над
/// [MultiLocationPoiWatcher] с фиксированным ключом локации —
/// логика радиуса/гистерезиса/точности существует в ОДНОМ
/// экземпляре, поведение и тесты одиночного вотчера сохранены.
class PoiProximityWatcher {

  PoiProximityWatcher({
    required List<Poi> pois,
    String islandId = '_single',
  }) : _watcher = MultiLocationPoiWatcher() {
    _watcher.add(islandId, pois);
  }

  final MultiLocationPoiWatcher _watcher;


  /// Обрабатывает новую позицию пользователя.
  ///
  /// Возвращает список POI, в радиус которых пользователь
  /// только что вошёл (по одному разу за «заход»). Фикс старше
  /// [LocationService.staleFixAge] (буфер фона/кеш датчика)
  /// игнорируется целиком (A1, 18-й проход).
  List<Poi> update(UserPosition position) {
    return [
      for (final entry in _watcher.update(position)) entry.$2,
    ];
  }
}

/// Вотчер сразу по нескольким локациям (A3, 8-й проход).
///
/// Пользователь идёт/плывёт вдоль берега между локациями —
/// автогид обязан ловить вход в радиус точек СОСЕДНИХ локаций,
/// а не только текущей выбранной. Ключ входа — составной
/// «локация/poi» (id POI повторяются между локациями), логика
/// точности/гистерезиса — как у [PoiProximityWatcher].
class MultiLocationPoiWatcher {

  /// Точки по составному ключу «локация/poi».
  final Map<String, LocatedPoi> _pois = {};

  /// Составные ключи, внутри радиуса которых пользователь
  /// сейчас находится.
  final Set<String> _inside = {};


  /// Добавляет точки локации (идемпотентно по составному ключу —
  /// повторная загрузка той же локации не дублирует записи).
  void add(String islandId, List<Poi> pois) {
    for (final poi in pois) {
      _pois['$islandId/${poi.id}'] = (islandId, poi);
    }
  }


  /// Обрабатывает новую позицию пользователя.
  ///
  /// Возвращает точки, в радиус которых пользователь только что
  /// вошёл (по одному разу за «заход»). Устаревший фикс
  /// ([LocationService.staleFixAge]) игнорируется (A1, 18-й проход).
  List<LocatedPoi> update(UserPosition position) {
    final entered = <LocatedPoi>[];

    if (LocationService.isStaleFix(position)) {
      return entered;
    }

    final accuracy = position.accuracy;

    for (final entry in _pois.values) {
      final key = '${entry.$1}/${entry.$2.id}';

      final distance = LocationService.distanceMeters(
        position.latitude,
        position.longitude,
        entry.$2.latitude,
        entry.$2.longitude,
      );

      // POI без radius срабатывают с дефолтом 50 м: раньше null
      // означал радиус 0, и точка не запускала гид никогда.
      final radius = entry.$2.radius ?? 50;

      final exitRadius = radius + exitHysteresis(radius, accuracy);

      if (distance <= radius) {

        // Грубый фикс не засчитываем как вход (A8).
        final accuracyOk =
            accuracy == null || accuracy <= max(radius, _maxEntryAccuracy);

        if (accuracyOk && _inside.add(key)) {
          entered.add(entry);
        }
      } else if (distance > exitRadius) {
        _inside.remove(key);
      }
    }

    return entered;
  }
}
