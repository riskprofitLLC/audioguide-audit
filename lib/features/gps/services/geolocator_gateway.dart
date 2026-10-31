import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import '../../../core/utils/logger.dart';
import '../models/user_position.dart';
import 'location_gateway.dart';

/// Реализация [LocationGateway] на платформенном пакете geolocator.
///
/// Работает на Android, iOS и web (браузерная геолокация).
class GeolocatorGateway implements LocationGateway {

  /// Таймаут «дешёвых» вызовов: метод-канал geolocator на
  /// отдельных устройствах/эмуляторах мог не отвечать ВООБЩЕ
  /// (проверено на API 36) — без таймаута плашка геолокации
  /// не появлялась, а тапы по ней молчали вечно.
  static const _quickCallTimeout = Duration(seconds: 5);

  /// Таймаут запроса разрешения: системный диалог открыт, пока
  /// пользователь его читает — Future живёт минуты.
  static const _requestTimeout = Duration(seconds: 60);

  /// Таймаут разовой позиции на native (A5, 17-й проход).
  ///
  /// Единая константа шлюза: UI показывает «до 15 с» — спиннер
  /// на кнопке не должен крутиться дольше обещанного. Изменяемая
  /// ради теста таймаута (мок канала не отвечает — иначе тест
  /// ждал бы 15 с реального времени).
  @visibleForTesting
  static Duration nativeLocateTimeout = const Duration(seconds: 15);

  /// Таймаут разовой позиции на web (A5).
  ///
  /// Браузерный дефолт getCurrentPosition — 10 с: явный timeLimit
  /// 20 с перекрывает его, иначе Chrome обрубал запрос ДО нашего
  /// таймаута (17-й проход, 53db091).
  @visibleForTesting
  static Duration webLocateTimeout = const Duration(seconds: 20);

  /// Настройки потока позиций под платформу.
  ///
  /// Вынесено в метод ради теста: настройки влияют на расход
  /// батареи (P8), а geolocator-объекты проверяемы напрямую.
  ///
  /// [isWeb] — параметр ради теста web-ветки (константа `kIsWeb`
  /// в тестах всегда false).
  @visibleForTesting
  static LocationSettings streamSettings({bool isWeb = kIsWeb}) {

    // Web (17-й проход): Chrome на Android отдаёт
    // TargetPlatform.android — без этой ветки на web уходили
    // AndroidSettings, которые geolocator_web не понимает.
    //
    // A14 (17-й проход): timeLimit из настроек потока УДАЛЁН —
    // у стоящего пользователя браузер кидал TIMEOUT, поток
    // умирал, а сервис перезапускал его с растущей паузой.
    // watchPosition без timeLimit просто ждёт свой первый фикс
    // столько, сколько нужно, — это и есть нужное поведение
    // живого потока. Разовая позиция (кнопка GPS) ограничена
    // своим [webLocateTimeout].
    if (isWeb) {
      return WebSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10,
        maximumAge: const Duration(minutes: 1),
      );
    }

    // Android: интервал заменяет «срочные» обновления geolocator —
    // позиции карте/автогиду нужны не чаще пары раз в секунду,
    // а датчик не разряжает батарею максимальной частотой.
    if (defaultTargetPlatform == TargetPlatform.android) {

      return AndroidSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10,
        intervalDuration: const Duration(seconds: 2),
      );
    }

    // iOS: ActivityType.fitness + автопауза — система сама
    // приостанавливает обновления, когда пользователь стоит
    // на месте, и будит поток при движении.
    if (defaultTargetPlatform == TargetPlatform.iOS) {

      return AppleSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10,
        activityType: ActivityType.fitness,
        pauseLocationUpdatesAutomatically: true,
      );
    }

    return const LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 10,
    );
  }


  /// Настройки разовой позиции (A5): web — medium-точность
  /// (WiFi/вышки, секунды вместо GPS-чипа) + разрешённый кеш;
  /// native — высокая точность GPS.
  ///
  /// [isWeb] — параметр ради теста web-ветки.
  @visibleForTesting
  static LocationSettings locateSettings({bool isWeb = kIsWeb}) {
    if (isWeb) {
      return WebSettings(
        accuracy: LocationAccuracy.medium,
        maximumAge: const Duration(minutes: 2),
        timeLimit: webLocateTimeout,
      );
    }

    // НЕ const: nativeLocateTimeout — мутабельная стот-константа
    // ради теста таймаута.
    return LocationSettings(
      accuracy: LocationAccuracy.high,
      // A8 (18-й проход): платформа отменяет запрос сама — внешний
      // timeout обрывает только Dart-ожидание, нативный опрос GPS
      // продолжал работать в фоне и зря тратил батарею.
      timeLimit: nativeLocateTimeout,
    );
  }

  @override
  Future<LocationPermissionStatus> checkPermission() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled()
          .timeout(_quickCallTimeout);

      if (!serviceEnabled) {
        return LocationPermissionStatus.serviceOff;
      }

      return _mapPermission(
        await Geolocator.checkPermission().timeout(_quickCallTimeout),
      );
    } catch (error, stack) {
      AppLogger.error(
        'Не удалось проверить разрешение на геолокацию',
        error: error,
        stackTrace: stack,
      );

      // A11 (18-й проход): зависший канал — НЕ «denied»: плашка
      // «Включить геолокацию» у человека с правами врала.
      return LocationPermissionStatus.unknown;
    }
  }

  @override
  Future<LocationPermissionStatus> ensurePermission() async {

    try {

      final serviceEnabled = await Geolocator.isLocationServiceEnabled()
          .timeout(_quickCallTimeout);

      if (!serviceEnabled) {

        AppLogger.warning('Служба геолокации отключена');

        return LocationPermissionStatus.serviceOff;
      }

      var permission =
          await Geolocator.checkPermission().timeout(_quickCallTimeout);

      // A9 (17-й проход): unableToDetermine — web-браузеры без
      // Permission API — раньше переводился в denied БЕЗ запроса:
      // человек видел подсказку, хотя диалог ему не показывали.
      // Запрашиваем и там: geolocator сам покажет системный
      // запрос или вернёт статус как есть.
      if (shouldRequestPermission(permission)) {

        permission =
            await Geolocator.requestPermission().timeout(_requestTimeout);
      }

      final status = _mapPermission(permission);

      AppLogger.info('[GeolocatorGateway] ensurePermission -> $status');

      return status;

    } catch (error, stack) {

      AppLogger.error(
        'Не удалось проверить разрешение на геолокацию',
        error: error,
        stackTrace: stack,
      );

      return LocationPermissionStatus.unknown;
    }
  }

  /// Нужно ли показать системный запрос для текущего статуса (A9,
  /// 17-й проход).
  ///
  /// `unableToDetermine` отдают web-браузеры без Permissions API
  /// (мимо base-канала: его int→enum расширение на этом значении
  /// бросает исключение) — раньше такой статус молча превращался
  /// в denied без единого запроса.
  @visibleForTesting
  static bool shouldRequestPermission(LocationPermission permission) {
    return permission == LocationPermission.denied ||
        permission == LocationPermission.unableToDetermine;
  }

  /// Штатный статус geolocator → статус приложения.
  static LocationPermissionStatus _mapPermission(
    LocationPermission permission,
  ) {
    switch (permission) {
      case LocationPermission.always:
      case LocationPermission.whileInUse:
        return LocationPermissionStatus.granted;

      case LocationPermission.deniedForever:
        return LocationPermissionStatus.deniedForever;

      case LocationPermission.denied:
      case LocationPermission.unableToDetermine:
        return LocationPermissionStatus.denied;
    }
  }


  @override
  Future<bool?> isLocationAccuracyReduced() async {
    // Web: getLocationAccuracy не реализован (MissingPlugin) —
    // тихо пропускаем.
    if (kIsWeb) {
      return null;
    }

    try {

      final status = await Geolocator.getLocationAccuracy()
          .timeout(_quickCallTimeout);

      if (status == LocationAccuracyStatus.reduced) {
        return true;
      }

      if (status == LocationAccuracyStatus.precise) {
        return false;
      }

      // Android < 12 отдаёт unknown — различить нельзя.
      return null;

    } catch (error) {

      AppLogger.warning(
        '[GeolocatorGateway] getLocationAccuracy недоступен: '
        '${error.runtimeType}',
      );

      return null;
    }
  }


  @override
  Future<UserPosition?> platformLastKnownPosition() async {

    // Web: у geolocator_web нет getLastKnownPosition.
    if (kIsWeb) {
      return null;
    }

    try {

      final position = await Geolocator.getLastKnownPosition()
          .timeout(_quickCallTimeout);

      if (position == null) {
        return null;
      }

      return _toUserPosition(position);

    } catch (error) {

      AppLogger.warning(
        '[GeolocatorGateway] getLastKnownPosition недоступен: '
        '${error.runtimeType}',
      );

      return null;
    }
  }

  @override
  Stream<bool> get serviceStatusChanges {

    // Web-реализация не поддерживает поток статуса службы.
    if (kIsWeb) {
      return const Stream.empty();
    }

    try {

      return Geolocator.getServiceStatusStream()
          .map((status) => status == ServiceStatus.enabled);

    } catch (error) {

      // Отдельные платформы бросают исключение синхронно.
      AppLogger.warning(
        '[GeolocatorGateway] getServiceStatusStream недоступен: '
        '${error.runtimeType}',
      );

      return const Stream.empty();
    }
  }


  @override
  Stream<UserPosition> get positions async* {

    final settings = streamSettings();

    try {

      AppLogger.info('[GeolocatorGateway] positions stream started');

      await for (final position
          in Geolocator.getPositionStream(
        locationSettings: settings,
      )) {

        // Самый горячий лог приложения (~1 тик/сек при активном
        // GPS): ленивый вариант + без самих координат (правило
        // logger.dart — координаты пользователя не логируются).
        AppLogger.infoFn(
          () => '[GeolocatorGateway] position '
              'acc=${position.accuracy.toStringAsFixed(1)}',
        );

        yield _toUserPosition(position);
      }

    } catch (error, stack) {

      AppLogger.error(
        'Поток геолокации прерван',
        error: error,
        stackTrace: stack,
      );
    }
  }


  @override
  Future<LocateResult> currentPosition() async {

    final isWeb = kIsWeb;

    try {

      AppLogger.info('[GeolocatorGateway] currentPosition requested');

      final position = await Geolocator.getCurrentPosition(
        locationSettings: locateSettings(isWeb: isWeb),
      ).timeout(
        isWeb ? webLocateTimeout : nativeLocateTimeout,
      );

      AppLogger.info('[GeolocatorGateway] currentPosition received');

      return LocatePosition(_toUserPosition(position));

    } on LocationServiceDisabledException {

      AppLogger.warning('[GeolocatorGateway] currentPosition: служба выключена');

      return const LocateServiceOff();

    } on PermissionDeniedException {

      AppLogger.warning('[GeolocatorGateway] currentPosition: нет разрешения');

      return const LocatePermissionDenied();

    } on TimeoutException {

      AppLogger.warning(
        '[GeolocatorGateway] currentPosition: таймаут '
        '(${isWeb ? webLocateTimeout : nativeLocateTimeout.inSeconds}с)',
      );

      return const LocateTimeout();

    } catch (error, stack) {

      // A4 (17-й проход): тип ошибки и платформа — БЕЗ самих
      // координат (правило logger.dart). Раньше здесь стояло
      // экранирование \$error — в лог писались литералы.
      AppLogger.error(
        '[GeolocatorGateway] currentPosition failed: '
        'type=${error.runtimeType} kIsWeb=$isWeb',
        error: error,
        stackTrace: stack,
      );

      return const LocateUnavailable();
    }
  }




  UserPosition _toUserPosition(Position position) {

    // Курс: 0 — «не измерено» и на Android (bearing), и в web
    // (coords.heading) — отличить «на север» от «неизвестно»
    // нельзя, поэтому ноль трактуем как отсутствие курса.
    final rawHeading = position.heading;

    return UserPosition(
      latitude: position.latitude,
      longitude: position.longitude,
      accuracy: position.accuracy,
      speed: position.speed,
      heading: rawHeading > 0 ? rawHeading : null,
      timestamp: position.timestamp,
    );
  }
}
