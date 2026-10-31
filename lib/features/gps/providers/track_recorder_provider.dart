import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/track_recorder.dart';
import '../utils/gpx_export.dart';
import 'location_providers.dart';

/// Состояние записи трека (29-й проход, П5).
class TrackRecorderState {

  const TrackRecorderState({
    required this.isRecording,
    required this.pointsCount,
    this.startedAt,
  });


  final bool isRecording;

  final int pointsCount;

  final DateTime? startedAt;
}


/// Провайдер записи собственного трека: держит [TrackRecorder]
/// и обновляет счётчик точек по каждому записанному GPS-тику.
final trackRecorderProvider =
    NotifierProvider<TrackRecorderNotifier, TrackRecorderState>(
  TrackRecorderNotifier.new,
);

class TrackRecorderNotifier extends Notifier<TrackRecorderState> {

  late final TrackRecorder _recorder;

  VoidCallback? _countListener;

  @override
  TrackRecorderState build() {
    _recorder = TrackRecorder(
      positions: ref.watch(locationServiceProvider).positions,
    );

    _countListener = () {
      if (state.isRecording) {
        state = TrackRecorderState(
          isRecording: true,
          pointsCount: _recorder.pointsCount.value,
          startedAt: state.startedAt,
        );
      }
    };

    _recorder.pointsCount.addListener(_countListener!);

    ref.onDispose(() {
      _recorder.pointsCount.removeListener(_countListener!);
      _recorder.dispose();
    });

    return const TrackRecorderState(
      isRecording: false,
      pointsCount: 0,
    );
  }


  /// Старт записи. Повторный вызов во время записи — no-op.
  void start() {
    if (state.isRecording) {
      return;
    }

    _recorder.start();

    state = TrackRecorderState(
      isRecording: true,
      pointsCount: 0,
      startedAt: _recorder.startedAt,
    );
  }


  /// Стоп записи: возвращает GPX-строку трека или null, если запись
  /// не была запущена или точек меньше двух.
  String? stopAndBuildGpx() {
    if (!state.isRecording) {
      return null;
    }

    final points = _recorder.stop();

    state = const TrackRecorderState(
      isRecording: false,
      pointsCount: 0,
    );

    if (points.length < 2) {
      return null;
    }

    final name = 'Трек ${_recorder.startedAt ?? DateTime.now()}';

    return buildGpxTrack(name: name, points: points);
  }
}
