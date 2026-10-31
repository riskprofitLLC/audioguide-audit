import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

import '../../../core/utils/logger.dart';
import 'background_audio.dart';


/// Тонкая абстракция над аудиоплеером.
///
/// Нужна, чтобы тестировать логику сервиса голосового
/// гида без платформенных каналов just_audio.
abstract class AudioGateway {


  Stream<PlayerState> get playerStateStream;


  Stream<Duration> get positionStream;


  Stream<Duration?> get durationStream;


  bool get playing;


  Future<void> setAsset(
    String path,
  );


  Future<void> play();


  Future<void> pause();


  Future<void> stop();


  Future<void> seek(
    Duration position,
  );


  Future<void> setSpeed(
    double speed,
  );


  Future<void> dispose();
}


/// Реализация на just_audio (Android/iOS/web).
final class JustAudioGateway implements AudioGateway {


  JustAudioGateway({
    AudioPlayer? player,
  }) : _player =
           player ??
               AudioPlayer();


  final AudioPlayer _player;


  @override
  Stream<PlayerState> get playerStateStream =>
      _player.playerStateStream;


  @override
  Stream<Duration> get positionStream =>
      _player.positionStream;


  @override
  Stream<Duration?> get durationStream =>
      _player.durationStream;


  @override
  bool get playing =>
      _player.playing;


  @override
  Future<void> setAsset(
    String path,
  ) async {
    // 28-й проход: источник подаём через setAudioSource с MediaItem
    // (см. background_audio.dart) — тогда just_audio_background ведёт
    // медиа-сессию: уведомление, lock screen и воспроизведение при
    // заблокированном экране. На web — обычный AudioSource.asset.
    await _player.setAudioSource(
      await assetAudioSource(path),
    );
  }


  /// Таймаут подтверждения старта воспроизведения: если за это
  /// время не пришло событие playing/ready и play() не упал —
  /// считаем, что старт состоялся (часть платформ шлёт состояние
  /// редко, блокировать очередь дольше нельзя).
  static const _playStartTimeout = Duration(seconds: 3);

  @override
  Future<void> play() async {
    // Future от play() не завершается, пока трек не прерван или не
    // доигран: на web это поведение HTML5-элемента, а на некоторых
    // эмуляторах Android ExoPlayer не переходит в processingState
    // ready, пока играет (virtual audio device). Если ждать его,
    // сериализованная очередь сервиса заблокируется и stop()/pause()
    // не выполнятся до конца трека. Поэтому сам future не ждём.
    //
    // Ошибка старта (автоплей-блокировка web, PlayerException)
    // обязана дойти до сервиса: ловим её отдельным каналом и
    // ждём ЛИБО подтверждение старта (событие playing/ready),
    // ЛИБО ошибку — что раньше. Таймаут считаем стартом, чтобы
    // не блокировать очередь сериализованных операций.
    final failure = Completer<Object>();

    unawaited(_player.play().catchError((Object error) {
      if (!failure.isCompleted) {
        failure.complete(error);
      }
      AppLogger.error(
        '[AudioGateway] play error',
        error: error,
      );
    }));

    final confirmed = _player.playerStateStream
        .firstWhere(
          (state) =>
              state.playing ||
              state.processingState == ProcessingState.ready,
        )
        .timeout(_playStartTimeout)
        .then<PlayerState?>(
          (state) => state,
          onError: (Object _) => null,
        );

    await Future.any<Object>([
      confirmed.then<Object>((value) => value ?? Object()),
      failure.future,
    ]);

    // Ошибка старта до подтверждения — пробрасываем в сервис,
    // чтобы UI показал «Не удалось воспроизвести аудио».
    if (failure.isCompleted) {
      throw await failure.future;
    }
  }


  @override
  Future<void> pause() =>
      _player.pause();


  @override
  Future<void> stop() async {
    // just_audio 0.10.x на web в stop() не ставит воспроизведение
    // на паузу: это лишь локальный Dart-флаг (playing=false), а
    // HTML5-элемент продолжает звучать. pause() реально заставляет
    // элемент замолчать, поэтому на web он вызывается явно.
    if (kIsWeb) {
      await _player.pause();
    }
    await _player.stop();
  }


  @override
  Future<void> seek(
    Duration position,
  ) =>
      _player.seek(position);

  @override
  Future<void> setSpeed(
    double speed,
  ) =>
      _player.setSpeed(speed);


  @override
  Future<void> dispose() =>
      _player.dispose();
}
