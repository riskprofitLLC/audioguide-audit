import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

import '../../../core/utils/logger.dart';
import 'audio_gateway.dart';


/// Сервис голосового гида.
///
/// Один плеер на всё приложение — воспроизведение не
/// прерывается при переходе между экранами. Обладает
/// защитой от повторного запуска одного и того же аудио:
/// повторный запрос файла, который уже звучит, его не
/// перезапускает.
final class AudioPlayerService {

  AudioPlayerService({
    AudioGateway? gateway,
  }) : _gateway =
           gateway ??
               JustAudioGateway() {
    _playerStateSub =
        _gateway.playerStateStream.listen(_onPlayerState);
    _positionSub =
        _gateway.positionStream.listen((position) {
          _lastPosition = position;
        });
    // Б12 (замечание Sonnet): длительность републикуется через
    // собственный фильтр — событие публикуется, только если оно
    // относится к ТЕКУЩЕМУ файлу. Раньше «запаздывающее» событие
    // старого файла приписывалось новому — listened_providers
    // отмечал новую точку на чужой длительности.
    //
    // Баг 9: событие длительности НОВОГО файла может прийти раньше
    // возврата setAsset (платформа отдаёт metadata до завершения
    // метода) — `_assetFile` ещё старый, и фильтр гасил событие.
    // `_pendingAsset` помечает «ожидаемый» ассет на время загрузки.
    _durationSub = _gateway.durationStream.listen((duration) {
      if (_assetFile == _currentFile ||
          _pendingAsset == _currentFile) {
        if (!_durationController.isClosed) {
          _durationController.add(duration);
        }
      }
    });
  }


  final AudioGateway _gateway;


  /// Поток текущего файла (последний отданный гейтвею ассет).
  ///
  /// Broadcast с реплеем: новый подписчик сразу получает
  /// актуальное значение. Нужен, чтобы виджеты плеера не
  /// показывали состояние чужого файла.
  final _currentFileController =
      StreamController<String?>.broadcast();

  /// Длительность, ПРИВЯЗАННАЯ к текущему файлу (Б12): события
  /// гейтвея относятся к ассету в плеере; публикация идёт только
  /// при совпадении с логическим текущим файлом.
  final _durationController =
      StreamController<Duration?>.broadcast();


  /// Позиции файлов на момент ухода с них — чтобы вернуться
  /// к прерванному треку с того же места.
  final Map<String, Duration> _positions = {};

  static const _maxCachedPositions = 20;


  StreamSubscription<PlayerState>? _playerStateSub;

  StreamSubscription<Duration>? _positionSub;

  StreamSubscription<Duration?>? _durationSub;

  /// Флаг полного уничтожения сервиса (пункт 10): после него
  /// setSpeed и другие публичные вызовы не обращаются к диспознутым
  /// объектам.
  bool _disposed = false;

  /// Файл, фактически загруженный в гейтвей последним успешным
  /// setAsset (Б12): им фильтруются события длительности.
  String? _assetFile;

  /// Файл, который грузится в гейтвей ПРЯМО СЕЙЧАС (баг 9,
  /// замечания Sonnet): помечается ДО setAsset — событие
  /// длительности нового файла приходит раньше возврата метода,
  /// когда `_assetFile` ещё указывает на прежний файл.
  String? _pendingAsset;


  /// Хвост очереди операций: все публичные методы сериализуются,
  /// чтобы конкурентные prepare()/play()/stop() не перемежались.
  Future<void> _op = Future.value();


  String? _currentFile;

  Duration _lastPosition = Duration.zero;

  /// Последнее состояние плеера (processingState).
  ///
  /// just_audio на web не сбрасывает `playing` при естественном
  /// завершении трека — после `completed` он продолжает числиться
  /// играющим, из-за чего кнопка «горит», а повторный play того же
  /// файла молча игнорируется. По этому флагу отличаем
  /// «дослушан до конца» от «реально играет».
  ProcessingState _lastProcessingState = ProcessingState.idle;


  /// Файл, загруженный в плеер (путь к ассету).
  String? get currentFile =>
      _currentFile;


  /// Поток смены загруженного файла (с реплеем текущего).
  Stream<String?> get currentFileStream =>
      Stream.multi((controller) {
        controller.add(_currentFile);
        final sub = _currentFileController.stream.listen(
          controller.add,
          onError: controller.addError,
          onDone: () {
            if (!controller.isClosed) {
              controller.close();
            }
          },
        );
        controller.onCancel = sub.cancel;
      });


  /// Звучит ли сейчас аудио (любой файл).
  bool get isPlaying =>
      _gateway.playing;


  /// Дослушан ли загруженный файл до конца (по последнему событию).
  ///
  /// Нужен виджетам плеера, созданным ПОСЛЕ запуска воспроизведения
  /// (автогид): поток состояния не реплеит прошлые события, поэтому
  /// начальное состояние виджет берёт из сервиса синхронно.
  bool get isCompleted =>
      _lastProcessingState == ProcessingState.completed;


  /// Поток состояния плеера (playing/processingState).
  Stream<PlayerState> get playerStateStream =>
      _gateway.playerStateStream;


  /// Текущая позиция воспроизведения.
  Stream<Duration> get positionStream =>
      _gateway.positionStream;


  /// Длительность загруженного аудио (null, пока неизвестна).
  ///
  /// Б12: поток отфильтрован — событие гарантированно относится
  /// к [currentFile] (смена файла публикует null, события чужих
  /// ассетов гасятся).
  Stream<Duration?> get durationStream =>
      _durationController.stream;

  /// Текущая скорость воспроизведения (P1-6: цикл 0.75/1/1.25/1.5).
  /// Notifier, а не стрим: значение меняется редко, а чип в
  /// карточке плеера слушает его через ValueListenableBuilder.
  final ValueNotifier<double> _speedNotifier = ValueNotifier(1.0);

  ValueListenable<double> get speedListenable => _speedNotifier;

  double get speed => _speedNotifier.value;

  /// Устанавливает скорость воспроизведения. Работает на лету,
  /// без очереди операций: setSpeed не конфликтует с загрузкой
  /// файлов и перемоткой. После dispose() — тихий no-op (пункт 10
  /// замечаний Sonnet): Notifier диспозится в конце очереди,
  /// вызов из осиротевшего виджета не должен бросать.
  Future<void> setSpeed(double value) async {
    if (_disposed) return;

    final clamped = value.clamp(0.5, 2.0);

    if (clamped == _speedNotifier.value) return;

    _speedNotifier.value = clamped;

    try {
      await _gateway.setSpeed(clamped);
    } catch (error) {
      AppLogger.error(
        '[AudioPlayerService] setSpeed error',
        error: error,
      );
    }
  }


  void _onPlayerState(
    PlayerState state,
  ) {

    _lastProcessingState = state.processingState;

    // Дослушанный до конца трек снова начинается с начала:
    // убираем закешированную позицию, иначе повторный play
    // «возобновил» бы его в самом конце.
    if (state.processingState ==
        ProcessingState.completed) {

      final file = _currentFile;

      if (file != null) {

        _positions.remove(file);
      }
    }
  }


  void _setCurrent(
    String? file,
  ) {

    final changed = _currentFile != file;

    _currentFile = file;

    // Позиция относится к ПРЕДЫДУЩЕМУ файлу: у нового она появится
    // только с первым событием positionStream. Без сброса уход с
    // нового файла (до его первого события) кешировал бы в него
    // позицию старого.
    _lastPosition = Duration.zero;

    // Б12: длительность предыдущего файла больше не его —
    // потребители сбрасываются до события нового файла.
    if (changed && !_durationController.isClosed) {
      _durationController.add(null);
    }

    if (!_currentFileController.isClosed) {

      _currentFileController.add(file);
    }
  }


  /// Выстраивает операцию в очередь за предыдущими.
  Future<void> _enqueue(
    Future<void> Function() action,
  ) {

    final result = _op.then((_) => action());

    // Ошибка конкретной операции не «рвёт» очередь.
    _op = result.then((_) {}, onError: (_) {});

    return result;
  }


  /// Запоминает позицию текущего файла перед уходом с него.
  Future<void> _cacheCurrentPosition() async {

    final file = _currentFile;

    if (file == null) {

      return;
    }

    if (_lastPosition <= Duration.zero) {

      return;
    }

    // Настоящий LRU: remove+insert перемещает ключ в конец.
    // Простой `_positions[file] = …` оставлял ключ на старом
    // месте, и «недавно прослушанный» трек вытеснялся первым.
    _positions.remove(file);

    _positions[file] = _lastPosition;

    if (_positions.length > _maxCachedPositions) {

      final oldest = _positions.keys.first;

      _positions.remove(oldest);
    }
  }


  /// Восстанавливает состояние после неудачной загрузки файла:
  /// возвращает прежний файл в плеер, чтобы потеря не была
  /// безвозвратной.
  Future<void> _restoreAfterError(
    String? previous,
    Object error,
    String operation,
    String filePath,
  ) async {

    AppLogger.error(
      '[AudioPlayerService] $operation failed for $filePath',
      error: error,
    );

    _setCurrent(previous);

    if (previous == null) {

      return;
    }

    try {

      await _gateway.stop();

      await _loadAsset(previous);

    } catch (_) {

      _setCurrent(null);
    }
  }


  /// Загружает ассет в гейтвей с пометкой «ожидаемого» (баг 9):
  /// события длительности, приходящие ВО ВРЕМЯ setAsset,
  /// относятся к этому файлу и не гасятся фильтром.
  Future<void> _loadAsset(String filePath) async {
    _pendingAsset = filePath;

    try {
      await _gateway.setAsset(filePath);

      _assetFile = filePath;
    } finally {
      _pendingAsset = null;
    }
  }


  /// Предзагружает файл, не начиная воспроизведение.
  ///
  /// Нужно, чтобы при открытии плеера сразу стала известна
  /// длительность файла (иначе до нажатия Play показывается
  /// «00:00»). Плеер глобальный, поэтому загрузка нового файла
  /// останавливает прежний. Чтобы не обрывать звучащий трек
  /// (например, при открытии шита другого POI во время
  /// прослушивания), файл грузится, только если сейчас ничего
  /// не играет; длительность в любом случае известна из байтов
  /// MP3, а реальная загрузка происходит по нажатию Play.
  Future<void> prepare(
    String filePath,
  ) async {

    AppLogger.info(
      '[AudioPlayerService] prepare $filePath '
      'current=$_currentFile playing=${_gateway.playing}',
    );

    await _enqueue(() async {

      if (_currentFile == filePath) {

        return;
      }

      // Дослушанный до конца трек на web всё ещё числится
      // играющим — предзагрузку это не должно останавливать.
      final completed =
          _lastProcessingState == ProcessingState.completed;

      if (_gateway.playing && !completed) {

        AppLogger.info(
          '[AudioPlayerService] prepare $filePath '
          'skip (another file is playing)',
        );

        return;
      }

      final previous = _currentFile;

      try {

        await _cacheCurrentPosition();

        _setCurrent(filePath);

        await _gateway.stop();

        await _loadAsset(filePath);

      } catch (error) {

        await _restoreAfterError(
          previous,
          error,
          'prepare',
          filePath,
        );
      }
    });
  }


  /// Воспроизводит файл.
  ///
  /// Если файл уже звучит — ничего не делает (защита от
  /// повторного запуска). Если звучит другой файл — он
  /// заменяется новым. Файл с сохранённой позицией
  /// возобновляется с неё (один раз), прерванный трек можно
  /// дослушать.
  Future<void> play(
    String filePath,
  ) async {

    AppLogger.info(
      '[AudioPlayerService] play $filePath '
      'current=$_currentFile playing=${_gateway.playing}',
    );

    await _enqueue(() => _playInternal(filePath));
  }


  Future<void> _playInternal(
    String filePath,
  ) async {

    // Дослушанный до конца файл — не «играющий»: повторный play
    // должен перезапустить его с начала, а не игнорироваться.
    final completed =
        _lastProcessingState == ProcessingState.completed;

    if (_currentFile == filePath &&
        _gateway.playing &&
        !completed) {

      AppLogger.info('[AudioPlayerService] skip (same file playing)');

      return;
    }

    if (_currentFile == filePath && completed) {

      // Дослушанный до конца файл перезапускаем с начала. На web
      // простое seek(0)+play() на том же HTML5-элементе не даёт
      // новых событий воспроизведения — playing/позиция не
      // обновляются, и строчка «замирает» при живом звуке. Поэтому
      // источник пересоздаём полностью, как при смене файла:
      // stop() сбрасывает плеер, setAsset() грузит файл заново.
      try {

        await _gateway.stop();

        await _loadAsset(filePath);

        // Трек перезапускается с начала: прежняя позиция (у конца
        // файла) больше не его позиция — не кешировать её при
        // паузе до первого события positionStream.
        _lastPosition = Duration.zero;

      } catch (error) {

        AppLogger.error(
          'Не удалось перезапустить завершённый трек',
          error: error,
        );

        rethrow;
      }
    }

    if (_currentFile != filePath) {

      final previous = _currentFile;

      try {

        await _cacheCurrentPosition();

        _setCurrent(filePath);

        // На web just_audio не переключает источник, пока звучит
        // предыдущий файл (старый аудиоэлемент продолжает играть).
        // stop() сбрасывает плеер в idle, после чего setAsset
        // грузит нужный файл с чистого элемента.
        await _gateway.stop();

        await _loadAsset(filePath);

        // Возобновляем трек с сохранённой позиции один раз.
        final resumeAt = _positions.remove(filePath);

        if (resumeAt != null && resumeAt > Duration.zero) {

          await _gateway.seek(resumeAt);
        }

      } catch (error) {

        await _restoreAfterError(
          previous,
          error,
          'play',
          filePath,
        );

        rethrow;
      }
    }

    try {

      await _gateway.play();

    } catch (error) {

      AppLogger.error(
        'Не удалось воспроизвести аудио $filePath',
        error: error,
      );

      rethrow;
    }
  }


  Future<void> pause() async {

    AppLogger.info('[AudioPlayerService] pause');

    await _enqueue(() async {

      try {

        await _gateway.pause();

      } catch (error) {

        AppLogger.error(
          'Не удалось поставить аудио на паузу',
          error: error,
        );
      }
    });
  }


  /// Полный сброс: источник очищается, позиция файла — тоже
  /// (следующее прослушивание начнётся с начала).
  Future<void> stop() async {

    AppLogger.info('[AudioPlayerService] stop');

    await _enqueue(() async {

      final file = _currentFile;

      _setCurrent(null);

      if (file != null) {

        _positions.remove(file);
      }

      try {

        await _gateway.stop();

        _assetFile = null;

      } catch (error) {

        AppLogger.error(
          'Не удалось остановить аудио',
          error: error,
        );
      }
    });
  }


  Future<void> seek(
    Duration position,
  ) async {

    AppLogger.info(
      '[AudioPlayerService] seek ${position.inMilliseconds} ms',
    );

    await _enqueue(() async {

      try {

        await _gateway.seek(position);

      } catch (error) {

        AppLogger.error(
          'Не удалось перемотать аудио',
          error: error,
        );
      }
    });
  }


  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;

    await _enqueue(() async {

      await _playerStateSub?.cancel();

      await _positionSub?.cancel();

      await _durationSub?.cancel();

      try {

        await _gateway.stop();

      } catch (_) {

        // Игнорируем: плеер и так уничтожается.
      }

      await _gateway.dispose();

      await _currentFileController.close();

      await _durationController.close();

      // Notifier диспозится ПОСЛЕ завершения очереди: отложенные
      // операции не читают диспознутый объект (пункт 10).
      _speedNotifier.dispose();
    });
  }
}
