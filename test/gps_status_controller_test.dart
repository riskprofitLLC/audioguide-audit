// GpsStatusController (D5/R1): машина состояний GPS-плашки вынесена
// из MapWidget — юнит-тесты переходов без виджетов.

import 'package:flutter_test/flutter_test.dart';

import 'package:island_guide/features/gps/services/location_gateway.dart';
import 'package:island_guide/features/map/controllers/gps_status_controller.dart';
import 'package:island_guide/features/map/presentation/widgets/map_location_status_pill.dart';

void main() {
  group('GpsStatusController', () {
    test('статус из разрешения: unknown — не «нет разрешения» (A11)', () {
      expect(
        GpsStatusController.statusFromPermission(
          LocationPermissionStatus.granted,
        ),
        MapLocationStatus.none,
      );

      expect(
        GpsStatusController.statusFromPermission(
          LocationPermissionStatus.unknown,
        ),
        MapLocationStatus.none,
      );

      expect(
        GpsStatusController.statusFromPermission(
          LocationPermissionStatus.denied,
        ),
        MapLocationStatus.noPermission,
      );

      expect(
        GpsStatusController.statusFromPermission(
          LocationPermissionStatus.deniedForever,
        ),
        MapLocationStatus.deniedForever,
      );

      expect(
        GpsStatusController.statusFromPermission(
          LocationPermissionStatus.serviceOff,
        ),
        MapLocationStatus.serviceOff,
      );
    });

    test('поиск сигнала и потеря: только поверх none, фикс снимает обе', () {
      final c = GpsStatusController();

      expect(c.markSearchingSignal(), isTrue);
      expect(c.status, MapLocationStatus.searchingSignal);

      // Повторный запрос не трогает статус.
      expect(c.markSearchingSignal(), isFalse);

      // Фикс снимает «ищем сигнал», wasLost = false.
      expect(c.onFixReceived(), isFalse);
      expect(c.status, MapLocationStatus.none);

      // 30 с без фикса — потеря; фикс возвращает wasLost = true.
      expect(c.markSignalLost(), isTrue);
      expect(c.onFixReceived(), isTrue);
      expect(c.status, MapLocationStatus.none);

      // markSignalLost поверх другой плашки не ставится.
      c.setStatus(MapLocationStatus.noPermission);
      expect(c.markSignalLost(), isFalse);
      expect(c.status, MapLocationStatus.noPermission);
    });

    test('разрешение выдано — info-статусы снимаются', () {
      final c = GpsStatusController();

      c.setStatus(MapLocationStatus.noPermission);
      expect(c.clearPermissionStatuses(), isTrue);
      expect(c.status, MapLocationStatus.none);

      // Повторно — без изменения.
      expect(c.clearPermissionStatuses(), isFalse);
    });

    test('служба вкл/выкл и точность по факту', () {
      final c = GpsStatusController();

      expect(c.serviceTurnedOff(), isTrue);
      expect(c.status, MapLocationStatus.serviceOff);

      expect(c.serviceTurnedOn(), isTrue);
      expect(c.status, MapLocationStatus.none);

      // reducedAccuracy ставится только поверх none.
      expect(c.applyReducedAccuracy(true), isTrue);
      expect(c.status, MapLocationStatus.reducedAccuracy);

      c.setStatus(MapLocationStatus.signalLost);
      expect(c.applyReducedAccuracy(true), isFalse);

      c.setStatus(MapLocationStatus.reducedAccuracy);
      expect(c.applyReducedAccuracy(false), isTrue);
      expect(c.status, MapLocationStatus.none);

      expect(c.markLowAccuracy(), isTrue);
      expect(c.status, MapLocationStatus.lowAccuracy);
    });
  });
}
