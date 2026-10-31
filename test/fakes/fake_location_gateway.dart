import 'dart:async';

import 'package:island_guide/features/gps/models/user_position.dart';
import 'package:island_guide/features/gps/services/location_gateway.dart';

/// Фейковый шлюз геолокации для тестов.
class FakeLocationGateway implements LocationGateway {

  /// Текущий статус разрешения (то, что вернёт checkPermission).
  LocationPermissionStatus status = LocationPermissionStatus.granted;

  /// Что вернёт ensurePermission — эмуляция «ответа на системный
  /// диалог» (например, granted после запроса).
  LocationPermissionStatus? requestResult;

  /// Что вернёт разовая позиция (A5, 17-й проход): по умолчанию
  /// успешный фикс, [nextLocateError] — ошибка.
  UserPosition? nextCurrentPosition;

  /// Ошибка разовой позиции вместо позиции (timeout/denied/…).
  LocateResult? nextLocateError;

  /// Задержка ответа разовой позиции — тест отмены поиска
  /// повторным тапом (A5).
  Duration? currentPositionDelay;

  /// Приблизительная геолокация (A13): `null` — «платформа не
  /// различает».
  bool? accuracyReduced;

  /// Последний фикс датчика ОС (B1, 18-й проход): `null` — платформа
  /// не хранит (как web).
  UserPosition? platformLastKnown;

  /// Состояния службы геолокации (A7).
  final _serviceStatus = StreamController<bool>.broadcast();

  final _positions =
      StreamController<UserPosition>.broadcast();

  /// Поток позиций, который ДОЛЖЕН завершиться (эмуляция смерти
  /// GPS-потока — отзыв разрешения): если задан, используется
  /// вместо [_positions].
  Stream<UserPosition>? positionsOverride;

  /// Сколько раз шлюз переподписывался на поток позиций
  /// (контроль ретраев LocationService, A7).
  int positionsSubscriptions = 0;

  final List<UserPosition> emitted = [];

  int checkPermissionCalls = 0;

  int ensurePermissionCalls = 0;

  /// Сколько раз запрашивалась разовая позиция (currentPosition).
  int currentPositionCalls = 0;

  /// Был ли запрос разрешения (системный диалог).
  bool get permissionRequested => ensurePermissionCalls > 0;


  @override
  Future<LocationPermissionStatus> checkPermission() async {

    checkPermissionCalls += 1;

    return status;
  }


  @override
  Future<LocationPermissionStatus> ensurePermission() async {

    ensurePermissionCalls += 1;

    return requestResult ?? status;
  }


  @override
  Stream<UserPosition> get positions {

    positionsSubscriptions += 1;

    return positionsOverride ?? _positions.stream;
  }


  @override
  Future<LocateResult> currentPosition() async {
    currentPositionCalls += 1;

    if (currentPositionDelay != null) {
      await Future<void>.delayed(currentPositionDelay!);
    }

    return nextLocateError ??
        LocatePosition(
          nextCurrentPosition ??
              const UserPosition(latitude: 43.0, longitude: 131.9),
        );
  }


  @override
  Future<bool?> isLocationAccuracyReduced() async => accuracyReduced;


  @override
  Future<UserPosition?> platformLastKnownPosition() async =>
      platformLastKnown;


  @override
  Stream<bool> get serviceStatusChanges => _serviceStatus.stream;


  void emit(UserPosition position) {

    emitted.add(position);

    _positions.add(position);
  }


  /// Эмуляция переключения службы геолокации (шторка телефона).
  void emitServiceStatus(bool enabled) {

    _serviceStatus.add(enabled);
  }


  Future<void> dispose() async {

    await _positions.close();

    await _serviceStatus.close();
  }
}
