import 'dart:async';

import 'package:just_audio/just_audio.dart';

import 'package:island_guide/features/audio/services/audio_gateway.dart';

/// Фейковый шлюз аудио для тестов без платформенных каналов.
class FakeAudioGateway implements AudioGateway {
  final List<String> loaded = [];
  int playCalls = 0;
  int stopCalls = 0;
  bool failSetAsset = false;

  /// Падает при следующем вызове play() (автоплей-блокировка web):
  /// ошибка старта обязана пробрасываться в сервис, а не глотаться.
  bool failPlay = false;

  /// Падает только при следующем вызове setAsset (удобно для
  /// проверки отката к прежнему файлу после неудачной загрузки).
  bool failSetAssetOnce = false;

  /// Гейт следующего setAsset (Б12): если задан, setAsset не
  /// завершается, пока тест не «откроет» гейт — эмулирует
  /// событие длительности нового файла, приходящее ДО
  /// завершения загрузки (баг 9, замечания Sonnet).
  Completer<void>? nextSetAssetGate;

  /// Гейт следующего stop(): окно, когда currentFile уже новый,
  /// ассет в плеере — ещё старый, и «запаздывающее» событие
  /// длительности старого файла обязано гаситься фильтром (Б12).
  Completer<void>? nextStopGate;

  final _stateCtrl = StreamController<PlayerState>.broadcast();
  final _positionCtrl = StreamController<Duration>.broadcast();
  final _durationCtrl = StreamController<Duration?>.broadcast();

  bool _playing = false;

  @override
  Stream<PlayerState> get playerStateStream => _stateCtrl.stream;

  @override
  Stream<Duration> get positionStream => _positionCtrl.stream;

  @override
  Stream<Duration?> get durationStream => _durationCtrl.stream;

  @override
  bool get playing => _playing;

  @override
  Future<void> setAsset(String path) async {
    if (failSetAsset || failSetAssetOnce) {
      failSetAssetOnce = false;
      throw StateError('setAsset failed');
    }

    final gate = nextSetAssetGate;

    if (gate != null) {
      nextSetAssetGate = null;

      await gate.future;
    }

    loaded.add(path);
    _playing = false;
    _emit(playing: false, processing: ProcessingState.loading);
  }

  @override
  Future<void> play() async {
    playCalls += 1;

    if (failPlay) {
      throw StateError('play blocked');
    }

    _playing = true;
    _emit(playing: true, processing: ProcessingState.ready);
  }

  @override
  Future<void> pause() async {
    _playing = false;
    _emit(playing: false, processing: ProcessingState.ready);
  }

  @override
  Future<void> stop() async {
    final stopGate = nextStopGate;

    if (stopGate != null) {
      nextStopGate = null;

      await stopGate.future;
    }

    stopCalls += 1;
    _playing = false;
    _emit(playing: false, processing: ProcessingState.idle);
  }

  final List<Duration> seeks = [];

  @override
  Future<void> seek(Duration position) async {
    seeks.add(position);
  }

  final List<double> speeds = [];

  @override
  Future<void> setSpeed(double speed) async {
    speeds.add(speed);
  }

  @override
  Future<void> dispose() async {
    await _stateCtrl.close();
    await _positionCtrl.close();
    await _durationCtrl.close();
  }

  void _emit({
    required bool playing,
    required ProcessingState processing,
  }) {
    _stateCtrl.add(
      PlayerState(
        playing,
        processing,
      ),
    );
  }

  void emitDuration(Duration duration) {
    _durationCtrl.add(duration);
  }

  void emitPosition(Duration position) {
    _positionCtrl.add(position);
  }

  /// Эмулирует естественное завершение трека на web: just_audio
  /// при `completed` НЕ сбрасывает playing (он остаётся true до
  /// pause/stop), поэтому состояние приходит как (playing: true,
  /// completed).
  void emitCompleted() {
    _playing = true;
    _emit(playing: true, processing: ProcessingState.completed);
  }

  /// Эмулирует возврат плеера в ready после перемотки с конца:
  /// ExoPlayer/HTML выходят из ended, когда позиция уходит
  /// с конца файла.
  void emitReady({bool playing = false}) {
    _playing = playing;
    _emit(playing: playing, processing: ProcessingState.ready);
  }
}
