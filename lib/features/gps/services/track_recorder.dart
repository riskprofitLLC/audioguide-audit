import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/user_position.dart';
import 'location_service.dart';

/// Запись собственного GPS-трека пользователя (29-й проход, П5).
///
/// Подписывается на поток позиций, пока запись включена; точки
/// фильтруются по расстоянию, чтобы трек не разрастался на месте.
class TrackRecorder {

  TrackRecorder({
    required Stream<UserPosition> positions,
  }) : _positions = positions;


  final Stream<UserPosition> _positions;

  /// Минимальное смещение между записанными точками (метры):
  /// стоящий пользователь не пишет «шум» в трек.
  static const double minPointDistanceMeters = 3;

  StreamSubscription<UserPosition>? _sub;

  final List<UserPosition> _points = [];

  /// Счётчик записанных точек — для UI во время записи.
  final ValueNotifier<int> pointsCount = ValueNotifier(0);

  DateTime? _startedAt;


  bool get isRecording => _sub != null;

  List<UserPosition> get points => List.unmodifiable(_points);

  DateTime? get startedAt => _startedAt;


  void start() {
    if (isRecording) {
      return;
    }

    _points.clear();

    pointsCount.value = 0;

    _startedAt = DateTime.now();

    _sub = _positions.listen(_onPosition);
  }


  void _onPosition(UserPosition position) {
    final last = _points.isEmpty ? null : _points.last;

    if (last != null &&
        LocationService.distanceMeters(
          last.latitude,
          last.longitude,
          position.latitude,
          position.longitude,
        ) <
            minPointDistanceMeters) {
      return;
    }

    _points.add(position);

    pointsCount.value = _points.length;
  }


  /// Останавливает запись и возвращает накопленные точки.
  List<UserPosition> stop() {
    _sub?.cancel();

    _sub = null;

    return List.unmodifiable(_points);
  }


  void dispose() {
    _sub?.cancel();

    pointsCount.dispose();
  }
}
