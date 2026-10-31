import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';

import '../../../../core/widgets/app_snack_bar.dart';
import '../../providers/audio_player_provider.dart';
import '../../services/audio_player_service.dart';

/// Компактное отслеживание состояния трека для малых UI
/// (мини-плеер, липкая панель POI, полоса прогресса пилюли) —
/// общий хелпер вместо копий подписок в каждом виджете
/// (баг 5 + D2, замечания Sonnet).
///
/// Подписки хранятся внутри и снимаются в [dispose]; виджет
/// перестраивается колбэком [onUpdate] (обычно `setState`).
class TrackStateWatcher {
  TrackStateWatcher({
    required AudioPlayerService service,
    required void Function() onUpdate,
  }) : _onUpdate = onUpdate {
    // Стартовое состояние — синхронно: поток не реплеит прошлые
    // события, а виджет, созданный после старта автогида, обязан
    // сразу видеть «играет».
    _file = service.currentFile;

    _playing = service.isPlaying && !service.isCompleted;

    _stateSub = service.playerStateStream.listen((state) {
      // Дослушанный трек — не «играет» (web не сбрасывает
      // playing при завершении).
      _playing = state.playing &&
          state.processingState != ProcessingState.completed;

      _onUpdate();
    });

    _fileSub = service.currentFileStream.listen((file) {
      _file = file;

      _onUpdate();
    });

    _positionSub = service.positionStream.listen((position) {
      _position = position;

      _onUpdate();
    });

    _durationSub = service.durationStream.listen((duration) {
      _duration = duration;

      _onUpdate();
    });
  }

  final void Function() _onUpdate;

  StreamSubscription<PlayerState>? _stateSub;

  StreamSubscription<String?>? _fileSub;

  StreamSubscription<Duration>? _positionSub;

  StreamSubscription<Duration?>? _durationSub;

  String? _file;

  bool _playing = false;

  Duration? _position;

  Duration? _duration;

  /// Файл, загруженный в плеер сейчас.
  String? get currentFile => _file;

  /// Играет ли трек (дослушанный до конца — не «играет»).
  bool get playing => _playing;

  /// Позиция воспроизведения текущего файла.
  Duration? get position => _position;

  /// Длительность текущего файла (null — пока неизвестна).
  Duration? get duration => _duration;

  /// Загружен ли в плеер файл [assetPath] (играет или на паузе).
  bool isLoaded(String assetPath) => _file == assetPath;

  void dispose() {
    _stateSub?.cancel();

    _fileSub?.cancel();

    _positionSub?.cancel();

    _durationSub?.cancel();
  }
}

/// Общий play/pause для компактных UI (мини-плеер, липкая панель
/// страницы POI) — одна реализация вместо двух копий (D2).
///
/// Пауза — сразу; продолжение — с перехватом ошибки сервиса
/// (битый ассет, автоплей-политика web) и снекбаром.
Future<void> toggleTrackPlayback(
  BuildContext context,
  WidgetRef ref, {
  required bool playing,
  required String assetPath,
}) async {
  final service = ref.read(audioPlayerServiceProvider);

  if (playing) {
    await service.pause();

    return;
  }

  try {
    await service.play(assetPath);
  } catch (_) {
    if (!context.mounted) {
      return;
    }

    showAppSnackBar(context, 'Не удалось воспроизвести аудио');
  }
}
