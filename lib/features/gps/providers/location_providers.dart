import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/logger.dart';
import '../models/user_position.dart';
import '../services/location_service.dart';

/// Синглтон сервиса геолокации.
///
/// onDispose останавливает платформенный GPS-поток и закрывает
/// контроллер: без него подписка жила бы до конца приложения.
final locationServiceProvider =
    Provider<LocationService>((ref) {

  final service = LocationService();

  ref.onDispose(service.dispose);

  return service;
});


/// Текущая позиция пользователя (поток обновлений).
///
/// Не эмитит события, пока не запрошено разрешение
/// или не получена первая позиция.
final userPositionProvider =
    StreamProvider<UserPosition>((ref) {

  AppLogger.info('[userPositionProvider] subscribed');

  final stream = ref.watch(locationServiceProvider).positions;

  return stream.transform(
    StreamTransformer<UserPosition, UserPosition>.fromHandlers(
      handleData: (position, sink) {
        // Ленивый лог: координаты пользователя не пишутся
        // (правило logger.dart), строка не интерполируется в release.
        AppLogger.infoFn(
          () => '[userPositionProvider] emitted '
              'acc=${position.accuracy?.toStringAsFixed(1) ?? '?'}',
        );
        sink.add(position);
      },
    ),
  );
});
