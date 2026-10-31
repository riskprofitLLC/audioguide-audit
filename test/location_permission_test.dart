// Статусы разрешения геолокации (P1-1, 7-й проход):
// checkPermission — мягкая проверка без системного диалога
// (карта показывает плашку), ensurePermission — явный запрос
// по тапу. Раньше ensurePermission возвращал bool и терял
// причину отказа: deniedForever/serviceOff выглядели одинаково.

import 'package:flutter_test/flutter_test.dart';

import 'package:island_guide/features/gps/services/location_gateway.dart';
import 'package:island_guide/features/gps/services/location_service.dart';

import 'fakes/fake_location_gateway.dart';

void main() {
  group('разрешение геолокации', () {
    test('checkPermission не запрашивает разрешение', () async {
      final gateway = FakeLocationGateway()
        ..status = LocationPermissionStatus.denied;

      final service = LocationService(gateway: gateway);

      final status = await service.checkPermission();

      expect(status, LocationPermissionStatus.denied);

      expect(gateway.checkPermissionCalls, 1);

      expect(
        gateway.permissionRequested,
        isFalse,
        reason: 'мягкая проверка не показывает системный диалог',
      );

      await gateway.dispose();
    });

    test('ensurePermission запрашивает разрешение по тапу', () async {
      final gateway = FakeLocationGateway()
        ..status = LocationPermissionStatus.denied
        ..requestResult = LocationPermissionStatus.granted;

      final service = LocationService(gateway: gateway);

      final status = await service.ensurePermission();

      expect(status, LocationPermissionStatus.granted);

      expect(gateway.permissionRequested, isTrue);

      await gateway.dispose();
    });

    test('deniedForever и serviceOff доходят до UI раздельно', () async {
      final gateway = FakeLocationGateway();

      final service = LocationService(gateway: gateway);

      gateway.status = LocationPermissionStatus.deniedForever;
      expect(
        await service.checkPermission(),
        LocationPermissionStatus.deniedForever,
        reason: 'отклонено навсегда — UI даёт кнопку «Настройки»',
      );

      gateway.status = LocationPermissionStatus.serviceOff;
      expect(
        await service.checkPermission(),
        LocationPermissionStatus.serviceOff,
        reason: 'служба выключена — UI ведёт в настройки местоположения',
      );

      await gateway.dispose();
    });
  });
}
