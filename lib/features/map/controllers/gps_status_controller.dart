/// Контроллер статуса GPS-плашки (D5/R1 аудита Sonnet): машина
/// состояний единой плашки верхнего левого угла карты вынесена
/// из MapWidget в чистый класс без BuildContext.
///
/// Варианты — [MapLocationStatus] из map_location_status_pill.dart.
/// Виджет держит setState/анонсы; контроллер решает переходы.
library;

import '../../gps/services/location_gateway.dart'
    show LocationPermissionStatus;
import '../presentation/widgets/map_location_status_pill.dart';

class GpsStatusController {

  /// Текущий показываемый статус (none — плашки нет).
  MapLocationStatus status = MapLocationStatus.none;

  /// Статус плашки для «сырого» статуса разрешения (B3).
  ///
  /// A11 (18-й проход): `unknown` → [MapLocationStatus.none] —
  /// «не смогли проверить» НЕ «нет разрешения», плашку не трогаем.
  static MapLocationStatus statusFromPermission(
    LocationPermissionStatus status,
  ) {
    switch (status) {
      case LocationPermissionStatus.granted:
      case LocationPermissionStatus.unknown:
        return MapLocationStatus.none;
      case LocationPermissionStatus.denied:
        return MapLocationStatus.noPermission;
      case LocationPermissionStatus.deniedForever:
        return MapLocationStatus.deniedForever;
      case LocationPermissionStatus.serviceOff:
        return MapLocationStatus.serviceOff;
    }
  }

  /// Смена статуса; true — статус изменился (виджет перестроится).
  bool setStatus(MapLocationStatus value) {
    if (status == value) {
      return false;
    }

    status = value;

    return true;
  }

  /// Применить статус разрешения (перепроверка при resume/тапе).
  bool applyPermission(LocationPermissionStatus permission) {
    return setStatus(statusFromPermission(permission));
  }

  /// Разрешение выдано: info-статусы (noPermission/deniedForever/
  /// serviceOff) снимаются.
  bool clearPermissionStatuses() {
    if (status == MapLocationStatus.noPermission ||
        status == MapLocationStatus.deniedForever ||
        status == MapLocationStatus.serviceOff) {
      return setStatus(MapLocationStatus.none);
    }

    return false;
  }

  /// Служба геолокации выключена в шторке телефона (A7).
  bool serviceTurnedOff() => setStatus(MapLocationStatus.serviceOff);

  /// Служба включена обратно: serviceOff снимается (подписка при
  /// этом жива — иначе статус ждёт _handlePermissionGranted).
  bool serviceTurnedOn() {
    if (status == MapLocationStatus.serviceOff) {
      return setStatus(MapLocationStatus.none);
    }

    return false;
  }

  /// Подписка на поток живая, но 15 с без первого фикса —
  /// «Ищем сигнал GPS…». Снимется первым фиксом.
  bool markSearchingSignal() {
    if (status != MapLocationStatus.none) {
      return false;
    }

    return setStatus(MapLocationStatus.searchingSignal);
  }

  /// 30 с без живого фикса — «Сигнал GPS потерян» (B1).
  bool markSignalLost() {
    if (status != MapLocationStatus.none) {
      return false;
    }

    return setStatus(MapLocationStatus.signalLost);
  }

  /// Пришёл фикс: плашки поиска/потери сигнала снимаются.
  /// Возвращает null, если статус не менялся; иначе wasLost —
  /// для анонса скринридеру «Сигнал GPS найден».
  bool? onFixReceived() {
    if (status == MapLocationStatus.searchingSignal ||
        status == MapLocationStatus.signalLost) {
      final wasLost = status == MapLocationStatus.signalLost;

      setStatus(MapLocationStatus.none);

      return wasLost;
    }

    return null;
  }

  /// Статус приблизительной точности по факту (A4/A13): true —
  /// плашка reducedAccuracy (только поверх none), false — снять.
  bool applyReducedAccuracy(bool? reduced) {
    if (reduced == true) {
      if (status != MapLocationStatus.none) {
        return false;
      }

      return setStatus(MapLocationStatus.reducedAccuracy);
    }

    if (reduced == false &&
        status == MapLocationStatus.reducedAccuracy) {
      return setStatus(MapLocationStatus.none);
    }

    return false;
  }

  /// Грубая точность (>100 м) затянулась >20 с — плашка lowAccuracy.
  bool markLowAccuracy() {
    if (status != MapLocationStatus.none) {
      return false;
    }

    return setStatus(MapLocationStatus.lowAccuracy);
  }
}
