import 'dart:async';
import 'dart:math';

import '../../../core/utils/logger.dart';
import '../../content/models/manifest.dart';
import '../models/user_position.dart';
import 'geolocator_gateway.dart';
import 'location_gateway.dart';

/// Сервис геолокации приложения.
///
/// Является фасадом над [LocationGateway]: даёт поток
/// позиций, запрос разрешений и однократное определение
/// координат. Не зависит от конкретной платформенной
/// реализации.
///
/// Поток позиций — один общий broadcast: все потребители
/// (карта, авто-аудио, провайдеры) делят один подписчик
/// на платформенный GPS. Это исключает создание множества
/// параллельных стримов (утечка ресурсов на устройстве).
final class LocationService {

  LocationService({
    LocationGateway? gateway,
  }) : _gateway = gateway ?? GeolocatorGateway() {

    _positionsController = StreamController<UserPosition>.broadcast(
      onListen: _onFirstListener,
      onCancel: _onLastListenerGone,
    );
  }


  final LocationGateway _gateway;

  late final StreamController<UserPosition> _positionsController;

  StreamSubscription<UserPosition>? _gatewaySub;

  bool _subscribed = false;

  int _retryAttempts = 0;

  Timer? _retryTimer;

  /// Последняя известная позиция.
  ///
  /// Нужна, чтобы поздние подписчики broadcast-потока (например,
  /// карта, открытая после первого GPS-фикса) сразу получали
  /// актуальную позицию, а не ждали следующего события от датчика.
  UserPosition? _lastPosition;

  /// Позиция старше этого возраста не реплеится новым подписчикам.
  ///
  /// Фикс двухчасовой давности (карту открыли заново, датчик
  /// молчит) — уже не «текущая позиция»: она уводила маркер
  /// пользователя в прошлое место без шанса обновиться.
  static const Duration _maxReplayAge = Duration(minutes: 2);

  /// Сколько раз переподписываться после сбоя GPS.
  static const int _maxRetryAttempts = 5;

  /// Максимальный возраст фикса, при котором он ещё «реакционный»
  /// (A1, 18-й проход): входы в радиус POI и обработка тиками карты
  /// игнорируют фиксы старше этого порога.
  ///
  /// Сценарий: буфер фона/кеш датчика — в поток выплёскивается пачка
  /// устаревших позиций (пользователь давно прошёл точку). Вход по
  /// такому фиксy запускал чужой рассказ. `null`-метка времени —
  /// «как раньше» (платформа не дала — считаем свежим).
  static const Duration staleFixAge = Duration(seconds: 30);

  /// Устарел ли фикс для реакций (входы в радиус, тики карты).
  static bool isStaleFix(
    UserPosition position, {
    Duration maxAge = staleFixAge,
  }) {

    final timestamp = position.timestamp;

    if (timestamp == null) {

      return false;
    }

    return DateTime.now().difference(timestamp) > maxAge;
  }


  /// Пауза между попытками после исчерпания быстрых ретраев.
  ///
  /// Без неё одна серия сбоев (тоннель, выключенный датчик)
  /// отключала GPS до перезапуска приложения: подписка
  /// оставалась живой, `_retryAttempts` не сбрасывался, и
  /// новых событий больше не приходило.
  static const Duration _slowRetryInterval = Duration(seconds: 60);


  /// Поток обновлений позиции пользователя.
  ///
  /// Broadcast-поток: события получают только активные
  /// подписчики, платформенный стрим создаётся один раз.
  /// Новому подписчику сразу отдаётся последняя известная
  /// позиция (если она есть и ещё свежая), затем — живые события.
  Stream<UserPosition> get positions {

    final live = _positionsController.stream;

    return Stream<UserPosition>.multi((controller) {

      final last = _lastPosition;

      if (last != null && _isFreshEnough(last)) {

        controller.add(last);
      }

      final sub = live.listen(
        controller.add,

        onError: controller.addError,

        onDone: controller.close,
      );

      controller.onCancel = sub.cancel;
    });
  }

  /// Свежа ли позиция для реплея новым подписчикам.
  ///
  /// Без метки времени (платформа может её не дать) реплеим как
  /// раньше: показать последнюю известную точку лучше, чем ждать
  /// следующего тика датчика.
  static bool _isFreshEnough(UserPosition position) {

    final timestamp = position.timestamp;

    if (timestamp == null) {

      return true;
    }

    return DateTime.now().difference(timestamp) < _maxReplayAge;
  }


  /// Проверяет разрешение БЕЗ системного диалога (P1-1, 7-й
  /// проход): карта при открытии показывает плашку, а не
  /// мгновенный запрос.
  Future<LocationPermissionStatus> checkPermission() {

    return _gateway.checkPermission();
  }


  /// Запрашивает разрешение на геолокацию (системный диалог).
  Future<LocationPermissionStatus> ensurePermission() {

    return _gateway.ensurePermission();
  }


  /// Однократное определение текущей позиции (A5, 17-й проход):
  /// типизированный результат вместо `null` на все случаи.
  ///
  /// A6: успешный фикс сразу попадает в [_lastPosition] и общий
  /// поток — `lastKnownPosition` (дистанции в поиске) и автогид
  /// видят позицию с кнопки, не дожидаясь тика живого потока
  /// (стоящий на месте пользователь его не получит —
  /// `distanceFilter: 10`).
  Future<LocateResult> currentPosition() async {
    final result = await _gateway.currentPosition();

    if (result is LocatePosition) {
      _onPosition(result.position);
    }

    return result;
  }


  /// Последняя известная позиция, если она ещё свежая.
  ///
  /// Синхронный геттер для «дешёвых» потребителей (подпись
  /// «~2 км» в поиске, A5, 11-й проход): НЕ будит датчик и НЕ
  /// запрашивает разрешение — отдаёт лишь то, что уже пришло
  /// живому потоку позиций (карта/автогид). Порог свежести —
  /// тот же, что у реплея новым подписчикам ([_maxReplayAge]).
  UserPosition? get lastKnownPosition {
    final last = _lastPosition;

    if (last == null || !_isFreshEnough(last)) {
      return null;
    }

    return last;
  }


  /// Приблизительная геолокация на устройстве? (A13, 17-й проход)
  /// Фасад над шлюзом: `null` — платформа не различает.
  Future<bool?> isLocationAccuracyReduced() {
    return _gateway.isLocationAccuracyReduced();
  }


  /// Последняя известная позиция ПЛАТФОРМЫ (B1, 18-й проход).
  ///
  /// Отличается от [lastKnownPosition]: это фикс датчика ОС,
  /// сохранённый без активной подписки — маркер показывает его
  /// приглушённым до первого живого фикса (native; web — null).
  Future<UserPosition?> platformLastKnownPosition() {
    return _gateway.platformLastKnownPosition();
  }


  /// Изменения состояния СЛУЖБЫ геолокации (A7, 17-й проход):
  /// выключение в шторке телефона видит карта без ожидания
  /// возврата в приложение (web — пустой поток).
  Stream<bool> get serviceStatusChanges {
    return _gateway.serviceStatusChanges;
  }


  void _onFirstListener() {

    _retryAttempts = 0;

    _start();
  }


  void _onLastListenerGone() {

    _stop();
  }


  void _start() {

    if (_subscribed) {
      return;
    }

    _subscribed = true;

    AppLogger.info('[LocationService] subscribing to gateway stream');

    _gatewaySub = _gateway.positions.listen(
      _onPosition,

      onError: (Object error, StackTrace stack) {

        AppLogger.error(
          '[LocationService] gateway stream error',
          error: error,
          stackTrace: stack,
        );

        _stop();

        _scheduleRetryIfAllowed();
      },

      onDone: () {

        AppLogger.info('[LocationService] gateway stream done');

        _stop();

        _scheduleRetryIfAllowed();
      },
    );
  }

  /// Ретраи — только пока геолокация вообще доступна (A7, 17-й
  /// проход).
  ///
  /// Раньше поток, умерший из-за отзыва разрешения или выключения
  /// службы, перезапускался бесконечно (быстрые попытки, затем раз
  /// в 60 с), а UI молчал. Теперь перед каждым ретраем проверяем
  /// разрешение: `checkPermission` возвращает serviceOff и для
  /// выключенной службы — оба случая останавливают цикл. Возврат
  /// прав/службы будит поток снаружи ([ensureGatewayActive]) —
  /// перепроверкой на resume в MapWidget или слушателем статуса
  /// службы.
  Future<void> _scheduleRetryIfAllowed() async {

    LocationPermissionStatus status;

    try {

      status = await _gateway.checkPermission();

    } catch (error) {

      // Сама проверка не удалась — ретраим, как раньше.
      AppLogger.warning(
        '[LocationService] проверка разрешения перед ретраем '
        'не удалась: ${error.runtimeType}',
      );

      _scheduleRetry();

      return;
    }

    // Ретраи — только пока геолокация точно недоступна (A7, 17-й
    // проход): отзыв разрешения и выключенная служба останавливают
    // цикл. `unknown` (канал не ответил, A11 18-го) — не «нет
    // прав», а «не смогли проверить»: продолжаем попытки.
    if (status == LocationPermissionStatus.denied ||
        status == LocationPermissionStatus.deniedForever ||
        status == LocationPermissionStatus.serviceOff) {

      AppLogger.warning(
        '[LocationService] GPS-поток завершён, разрешение=$status — '
        'ретраи остановлены',
      );

      return;
    }

    _scheduleRetry();
  }


  /// Будит платформенную подписку, если она умерла, а слушатели
  /// живы (A7, 17-й проход).
  ///
  /// Сценарий: разрешение отозвали — поток завершился, ретраи
  /// остановлены; в настройках доступ вернули — никто не
  /// перезапустил бы подписку (контроллер всё это время держал
  /// слушателей, его `onListen` больше не сработает). Вызов после
  /// повторной выдачи прав/включения службы запускает поток.
  void ensureGatewayActive() {

    if (_positionsController.hasListener &&
        !_positionsController.isClosed &&
        !_subscribed) {

      AppLogger.info('[LocationService] reactivating gateway stream');

      _retryAttempts = 0;

      _start();
    }
  }

  /// Останавливает платформенную подписку GPS (A1/A12).
  ///
  /// A1 (18-й проход): прежний `pause()` подписки на broadcast-поток
  /// лишь буферизовал события — нативный опрос продолжал жечь
  /// батарею, буфер рос без ограничения, а при возврате в
  /// приложение выплёвывалась пачка устаревших фиксов (вход по
  /// ним запускал чужой рассказ, см. [staleFixAge]). Теперь
  /// подписка ОТМЕНЯЕТСЯ: слушатели broadcast-потока и последняя
  /// позиция сохраняются — [resumePlatformStream] подписывается
  /// заново. Воспроизведение аудио не затрагивается: глохнет
  /// только поток позиций, плеер живёт своей очередью.
  void pausePlatformStream() {

    _retryTimer?.cancel();

    _retryTimer = null;

    _gatewaySub?.cancel();

    _gatewaySub = null;

    _subscribed = false;
  }

  /// Возобновляет платформенную подписку GPS после остановки:
  /// новая подписка на поток шлюза (свежие фиксы, без буфера).
  void resumePlatformStream() {

    if (_subscribed || _positionsController.isClosed) {
      return;
    }

    if (_positionsController.hasListener) {

      _retryAttempts = 0;

      _start();
    }
  }

  void _onPosition(UserPosition position) {

    _retryAttempts = 0;

    _lastPosition = position;

    if (!_positionsController.isClosed) {

      _positionsController.add(position);
    }
  }


  void _stop() {

    _gatewaySub?.cancel();

    _gatewaySub = null;

    _subscribed = false;

    _retryTimer?.cancel();
    _retryTimer = null;
  }

  void dispose() {
    _stop();
    _positionsController.close();
  }


  void _scheduleRetry() {

    _retryAttempts++;

    final attempt = _retryAttempts;

    // После быстрых попыток не сдаёмся навсегда: переходим в
    // редкие медленные ретраи, чтобы GPS восстановился сам,
    // как только причина сбоев исчезнет.
    final slow = attempt > _maxRetryAttempts;

    final delay = slow
        ? _slowRetryInterval
        : Duration(seconds: attempt * 2);

    // В медленном режиме не спамим лог на каждую попытку —
    // только в момент перехода.
    if (!slow || attempt == _maxRetryAttempts + 1) {

      AppLogger.warning(
        '[LocationService] retry GPS in ${delay.inSeconds}s '
        '(attempt $attempt${slow ? ', slow mode' : ''})',
      );
    }

    _retryTimer?.cancel();
    _retryTimer = Timer(delay, () {

      if (_positionsController.hasListener &&
          !_positionsController.isClosed) {

        _start();
      }
    });
  }


  /// Азимут (пеленг) из точки 1 в точку 2, градусы 0–360
  /// (0 — север, 90 — восток). П2, 12-й проход: «курс на
  /// ближайшую точку» на карте.
  static double bearingDegrees(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    final dLon = _toRadians(lon2 - lon1);

    final y = sin(dLon) * cos(_toRadians(lat2));

    final x = cos(_toRadians(lat1)) * sin(_toRadians(lat2)) -
        sin(_toRadians(lat1)) * cos(_toRadians(lat2)) * cos(dLon);

    // atan2 в радианах (-pi..pi); перевод в компасные градусы.
    final degrees = _toDegrees(atan2(y, x));

    return (degrees + 360) % 360;
  }


  /// Расстояние от точки до прямоугольника [bounds] (метры;
  /// 0 — точка внутри). Единая реализация для автогида (выбор
  /// локаций-кандидатов) и карты («далеко от региона») — раньше
  /// две копии (D2, замечания Sonnet).
  static double distanceToBoundsMeters(
    double lat,
    double lng,
    MapBounds bounds,
  ) {
    final clampLat = lat < bounds.south
        ? bounds.south
        : (lat > bounds.north ? bounds.north : lat);

    final clampLng = lng < bounds.west
        ? bounds.west
        : (lng > bounds.east ? bounds.east : lng);

    return distanceMeters(
      lat,
      lng,
      clampLat,
      clampLng,
    );
  }


  /// Дистанция по сфере между двумя координатами (метры).
  ///
  /// Формула гаверсинусов — достаточно точна для
  /// коротких расстояния (несколько километров).
  static double distanceMeters(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {

    const earthRadius = 6371000.0;

    final dLat = _toRadians(lat2 - lat1);

    final dLon = _toRadians(lon2 - lon1);

    final a =
        sin(dLat / 2) * sin(dLat / 2) +
        cos(_toRadians(lat1)) *
            cos(_toRadians(lat2)) *
            sin(dLon / 2) *
            sin(dLon / 2);

    final c = 2 * atan2(sqrt(a), sqrt(1 - a));

    return earthRadius * c;
  }


  static double _toRadians(double degrees) {

    return degrees * pi / 180;
  }


  /// Градусы из радиан.
  static double _toDegrees(double radians) {

    return radians * 180 / pi;
  }
}
