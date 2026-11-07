// Тесты платформенных настроек потока геолокации (батарея).

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';

import 'package:island_guide/features/gps/services/geolocator_gateway.dart';

void main() {
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
  });

  group('GeolocatorGateway.streamSettings', () {
    test('Android — интервал опроса 2 с (батарея)', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;

      final settings = GeolocatorGateway.streamSettings();

      expect(settings, isA<AndroidSettings>());

      final android = settings as AndroidSettings;

      expect(
        android.intervalDuration,
        const Duration(seconds: 2),
        reason: 'без интервала geolocator опрашивает GPS с '
            'максимальной частотой',
      );
      expect(android.distanceFilter, 10);
    });

    test('iOS — автопауза при простое и тип активности', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;

      final settings = GeolocatorGateway.streamSettings();

      expect(settings, isA<AppleSettings>());

      final apple = settings as AppleSettings;

      expect(
        apple.pauseLocationUpdatesAutomatically,
        isTrue,
        reason: 'iOS умеет сам останавливать обновления, пока '
            'пользователь не двигается',
      );
      expect(apple.activityType, ActivityType.fitness);
      expect(apple.distanceFilter, 10);
    });

    test('прочие платформы — базовые LocationSettings', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;

      final settings = GeolocatorGateway.streamSettings();

      expect(settings, isA<LocationSettings>());
      expect(settings, isNot(isA<AndroidSettings>()));
      expect(settings, isNot(isA<AppleSettings>()));
      expect(settings.accuracy, LocationAccuracy.high);
      expect(settings.distanceFilter, 10);
    });
  });

  group('GeolocatorGateway.streamSettings — web (A14, 17-й проход)', () {
    test('без timeLimit и с разрешённым кешем — поток не умирает у стоящего',
        () {
      // kIsWeb в тестах всегда false — web-ветка проверяется параметром.
      final settings = GeolocatorGateway.streamSettings(isWeb: true);

      expect(settings, isA<WebSettings>());

      final web = settings as WebSettings;

      expect(
        web.timeLimit,
        isNull,
        reason: 'timeLimit убран из потока: стоящий пользователь '
            'получал TIMEOUT, поток умирал, сервис перезапускал его '
            'с растущей паузой (A14)',
      );

      expect(web.maximumAge, const Duration(minutes: 1));
      expect(web.distanceFilter, 10);
      expect(web.accuracy, LocationAccuracy.high);
    });
  });

  group('GeolocatorGateway.locateSettings (A5, 17-й проход)', () {
    test('web — medium-точность, кеш и timeLimit 20 с (выше дефолта 10 с)',
        () {
      final settings = GeolocatorGateway.locateSettings(isWeb: true);

      expect(settings, isA<WebSettings>());

      final web = settings as WebSettings;

      expect(web.accuracy, LocationAccuracy.medium);
      expect(web.maximumAge, const Duration(minutes: 2));
      expect(web.timeLimit, GeolocatorGateway.webLocateTimeout);
      expect(
        GeolocatorGateway.webLocateTimeout.inSeconds,
        lessThanOrEqualTo(20),
        reason: 'согласованный таймаут UI: не более 20 с на web (A5)',
      );
    });

    test('native — высокая точность, таймаут не более 15 с', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;

      final settings = GeolocatorGateway.locateSettings();

      expect(settings, isA<LocationSettings>());
      expect(settings.accuracy, LocationAccuracy.high);

      expect(
        GeolocatorGateway.nativeLocateTimeout.inSeconds,
        lessThanOrEqualTo(15),
        reason: 'согласованный таймаут UI: не более 15 с на native (A5)',
      );
    });

    test('native — платформа отменяет запрос сама (A8, 18-й проход)', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;

      final settings = GeolocatorGateway.locateSettings();

      expect(
        settings.timeLimit,
        GeolocatorGateway.nativeLocateTimeout,
        reason: 'внешний timeout обрывает только Dart-ожидание — '
            'нативный опрос продолжал работать в фоне',
      );
    });
  });
}
