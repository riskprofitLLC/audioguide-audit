/// Подлёт камеры к позиции пользователя (кнопка GPS).
library;

import 'package:maplibre_gl/maplibre_gl.dart';

import '../../../core/utils/logger.dart';
import '../../gps/models/user_position.dart';

/// Вынесено из `MapWidget` в тестируемый модуль по той же причине, что
/// и [UserMarkerSource]: логика подлёта ломалась молча.
///
/// **Регрессия (найдена веб-пробой 07.11.2026):** подлёт спрашивал
/// текущий зум через `MapLibreMapController.queryCameraPosition()`, а
/// `maplibre_gl_web` этот метод НЕ реализует — он бросает
/// `UnimplementedError` (`lib/src/maplibre_web_gl_platform.dart`,
/// «Web implementation: MapLibre GL JS doesn't have direct camera
/// position query»). Ошибка глушилась catch'ем, поэтому на web
/// подлёт не случался НИКОГДА: кнопка GPS запоминала позицию,
/// переводилась в режим «следю за мной», но карта оставалась там, где
/// была — с точки зрения пользователя кнопка не работает ни в одном
/// браузере (Android и iOS alike).
///
/// Зум теперь приходит ИЗ СОБЫТИЙ камеры (`onCameraMove`) — он есть на
/// всех платформах, включая web.

/// Минимальный зум подлёта к позиции пользователя.
///
/// В режиме «все регионы» на меньшем масштабе точка теряется среди
/// кластеров POI.
const double kLocateMinZoom = 15.0;

/// Зум подлёта: не ниже [kLocateMinZoom], но и не отдаляем
/// пользователя, если он сам приблизил карту сильнее.
///
/// [currentZoom] — запомненный зум камеры; `null` (камера ещё не
/// двигалась) — минимальный.
double locateZoomFor(double? currentZoom) {
  if (currentZoom == null) {
    return kLocateMinZoom;
  }

  return currentZoom < kLocateMinZoom ? kLocateMinZoom : currentZoom;
}

/// Анимация камеры (узкий интерфейс над контроллером — ради фейка).
typedef CameraAnimator = Future<bool?> Function(CameraUpdate update);

/// Подлёт камеры к позиции: центр + зум [locateZoomFor].
///
/// Ошибки камеры глушатся (контроллер мог уже уничтожаться) — тик GPS
/// не должен падать из-за неё.
Future<void> flyCameraToPosition(
  UserPosition position, {
  required double? currentZoom,
  required CameraAnimator animate,
}) async {
  try {
    await animate(
      CameraUpdate.newLatLngZoom(
        LatLng(position.latitude, position.longitude),
        locateZoomFor(currentZoom),
      ),
    );
  } catch (error) {
    AppLogger.warning('[LocateCamera] fly camera failed: $error');
  }
}
