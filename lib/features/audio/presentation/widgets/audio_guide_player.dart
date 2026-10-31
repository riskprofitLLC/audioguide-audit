import 'dart:async';
import '../../../../core/utils/format.dart';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../app/theme.dart';
import '../../../../core/widgets/app_snack_bar.dart';
import '../../providers/audio_player_provider.dart';
import '../../services/audio_player_service.dart';
import '../../../settings/providers/settings_providers.dart';
import '../../services/audio_wave.dart';
import '../../services/mp3_duration.dart';


/// Плеер голосового гида с визуальной звуковой дорожкой.
///
/// Показывает декоративную волну (массив столбиков) с прогрессом
/// воспроизведения, позволяет перематывать в любое место тапом
/// или перетаскиванием по дорожке, а также стрелками ±10 секунд.

class AudioGuidePlayer extends ConsumerStatefulWidget {

  const AudioGuidePlayer({
    super.key,
    required this.assetPath,
    this.audioMs,
    this.wave,
  });


  /// Путь к ассету аудио (например,
  /// `content/gemiler/audio/poi-01.mp3`).
  final String assetPath;


  /// Длительность аудио из poi.json (A8, 8-й проход): плеер
  /// показывает её сразу, не грузя весь mp3 через rootBundle
  /// ради цифры (на web — двойная загрузка вместе с плеером).
  final int? audioMs;


  /// Огибающая громкости (base64, B5) — реальная волна дорожки.
  final String? wave;


  @override
  ConsumerState<AudioGuidePlayer> createState() =>
      _AudioGuidePlayerState();
}


class _AudioGuidePlayerState extends ConsumerState<AudioGuidePlayer> {

  /// Какой файл сейчас загружен в глобальный плеер. Состояние
  /// плеера глобальное, поэтому дорожка учитывает только события,
  /// относящиеся к своему файлу: если фоном (автогидом) запущен
  /// другой трек, этот плеер не должен показывать его прогресс.
  String? _currentFile;

  bool _ownPlaying = false;

  bool _ownCompleted = false;

  StreamSubscription<PlayerState>? _stateSub;

  StreamSubscription<String?>? _fileSub;


  @override
  void initState() {

    super.initState();

    final service =
        ref.read(audioPlayerServiceProvider);

    _currentFile = service.currentFile;

    // Автогид мог запустить (или дослушать) этот файл ещё ДО
    // создания виджета: поток состояния не реплеит прошлые события,
    // поэтому стартовое состояние берём из сервиса синхронно —
    // иначе кнопка показывала бы «Play», пока трек уже звучит.
    _ownPlaying = service.isPlaying && !service.isCompleted;

    _ownCompleted = service.isCompleted;

    _stateSub = service.playerStateStream.listen((state) {

      if (!mounted) {

        return;
      }

      setState(() {

        _ownPlaying = state.playing;

        _ownCompleted =
            state.processingState == ProcessingState.completed;
      });
    });

    _fileSub = service.currentFileStream.listen((file) {

      if (!mounted) {

        return;
      }

      setState(() {

        _currentFile = file;
      });
    });
  }


  @override
  void dispose() {

    _stateSub?.cancel();

    _fileSub?.cancel();

    super.dispose();
  }


  @override
  Widget build(BuildContext context) {

    final service =
        ref.watch(audioPlayerServiceProvider);

    final theme = Theme.of(context);

    // Активна дорожка, только если глобальный плеер загрузил
    // именно её файл.
    final active = _currentFile == widget.assetPath;

    // Пейсист скорости (P2, 7-й проход): первое чтение применяет
    // сохранённую скорость к плееру, смена — пишет настройку.
    ref.watch(playbackSpeedProvider);

    return _TrackCard(
      service: service,
      assetPath: widget.assetPath,
      audioMs: widget.audioMs,
      wave: widget.wave,
      onSpeedSelected: (speed) =>
          ref.read(playbackSpeedProvider.notifier).setSpeed(speed),
      // Дослушанный трек — не «играет»: на web just_audio не
      // сбрасывает playing при завершении, иначе кнопка «горела»
      // бы бесконечно.
      playing: active && _ownPlaying && !_ownCompleted,
      active: active,
      completed: active && _ownCompleted,
      theme: theme,
    );
  }
}


/// Карточка с дорожкой, перемоткой и кнопками.
class _TrackCard extends StatefulWidget {

  const _TrackCard({
    required this.service,
    required this.assetPath,
    required this.onSpeedSelected,
    required this.playing,
    required this.active,
    required this.completed,
    required this.theme,
    this.audioMs,
    this.wave,
  });


  final AudioPlayerService service;

  final String assetPath;

  /// Длительность из poi.json (A8): без чтения байтов файла.
  final int? audioMs;

  /// Огибающая громкости (B5): реальная волна вместо
  /// декоративной.
  final String? wave;

  /// Смена скорости (P2, 7-й проход): персист + применение к
  /// глобальному плееру одной операцией (playbackSpeedProvider).
  final ValueChanged<double> onSpeedSelected;

  final bool playing;

  /// Загружен ли в плеер именно файл этой дорожки. Если нет —
  /// показывается «00:00» без прогресса, а перемотка/пропуск
  /// игнорируются, чтобы не трогать чужой трек.
  final bool active;

  /// Дослушан ли текущий файл до конца (повторный Play
  /// перезапускает его с начала).
  final bool completed;

  final ThemeData theme;


  @override
  State<_TrackCard> createState() => _TrackCardState();
}


class _TrackCardState extends State<_TrackCard>
    with SingleTickerProviderStateMixin {

  Duration _position = Duration.zero;

  Duration? _duration;

  /// Доля дорожки под пальцем во время перетаскивания
  /// (-1 — перетаскивания нет). Это только предпросмотр: реальная
  /// перемотка происходит один раз, в конце жеста.
  double _dragFraction = -1;

  StreamSubscription<Duration>? _positionSub;

  StreamSubscription<Duration?>? _durationSub;

  /// Длительность, посчитанная из байтов файла. Пока она не
  /// известна, длительность берётся из стрима глобального плеера
  /// (fallback для тестов и редких форматов).
  Duration? _parsedDuration;


  /// Визуальная волна — детерминированная по пути файла,
  /// чтобы не мигала при перестроениях. НЕ late final (баг 4,
  /// замечания Sonnet): шторка «Сейчас играет» переиспользует
  /// карточку при смене трека — волна пересчитывается в
  /// didUpdateWidget.
  List<double> _wave = const [];

  /// «Живая» волна: столбики у плейхеда плавно колышутся,
  /// пока идёт воспроизведение. Тикер перерисовывает только
  /// CustomPaint волны (repaint-листенер), без setState.
  late final AnimationController _waveMotion;

  static const double _skipSeconds = 10;

  /// Период колыхания волны.
  static const Duration _waveMotionPeriod =
      Duration(milliseconds: 1400);


  @override
  void initState() {

    super.initState();

    // Реальная огибающая из poi.json (B5) — иначе декоративная
    // волна, детерминированная по пути файла.
    _wave = decodeWaveEnvelope(widget.wave) ?? _buildWave(widget.assetPath);
    _waveMotion = AnimationController(
      vsync: this,
      duration: _waveMotionPeriod,
    );

    // Трек мог заиграть автогидом ещё до создания карточки;
    // синхронизация волны — в didChangeDependencies (MediaQuery
    // для Reduce Motion нельзя читать в initState).
    _prepare(widget.assetPath);

    _loadDuration(widget.assetPath);

    _positionSub =
        widget.service.positionStream.listen((position) {

          // Игнорируем позицию чужого файла (автогид мог
          // переключить плеер на другой трек).
          if (!mounted ||
              widget.service.currentFile != widget.assetPath) {

            return;
          }

          setState(() {
            _position = position;
          });
        });

    _durationSub =
        widget.service.durationStream.listen((duration) {

          if (!mounted ||
              _parsedDuration != null ||
              widget.service.currentFile != widget.assetPath) {

            return;
          }

          setState(() {
            _duration = duration;
          });
        });
  }


  @override
  void didUpdateWidget(_TrackCard oldWidget) {

    super.didUpdateWidget(oldWidget);

    // Волна — по факту ассета/огибающей (баг 4): карточка
    // переиспользуется шторкой «Сейчас играет» на смене трека —
    // волна прежнего файла не должна оставаться.
    if (oldWidget.assetPath != widget.assetPath ||
        oldWidget.wave != widget.wave) {

      _wave =
          decodeWaveEnvelope(widget.wave) ?? _buildWave(widget.assetPath);
    }

    // Старт/стоп «живой» волны — по playing.
    if (widget.playing != oldWidget.playing) {

      _syncWaveMotion();
    }

    if (oldWidget.assetPath != widget.assetPath) {

      // Сбрасываем длительность/позицию старого файла, пока не
      // подоспеет длительность нового (_loadDuration). Иначе после
      // смены файла UI показывал бы цифры прошлого трека.
      _parsedDuration = null;

      _duration = null;

      _position = Duration.zero;

      _dragFraction = -1;

      _prepare(widget.assetPath);

      _loadDuration(widget.assetPath);
    }
  }


  /// Считает длительность файла: из poi.json сразу (A8, 8-й
  /// проход), иначе — из байтов (фолбэк для старого контента и
  /// тестов).
  Future<void> _loadDuration(String assetPath) async {

    final knownMs = widget.audioMs;

    if (knownMs != null && knownMs > 0) {

      if (!mounted || assetPath != widget.assetPath) {

        return;
      }

      final duration = Duration(milliseconds: knownMs);

      setState(() {

        _parsedDuration = duration;

        _duration = duration;
      });

      return;
    }

    final duration = await mp3DurationOfAsset(assetPath);

    if (!mounted || assetPath != widget.assetPath) {

      return;
    }

    setState(() {

      _parsedDuration = duration;

      if (duration != null) {

        _duration = duration;
      }
    });
  }


  @override
  void dispose() {

    _positionSub?.cancel();

    _durationSub?.cancel();

    _waveMotion.dispose();

    super.dispose();
  }


  @override
  Widget build(BuildContext context) {

    final theme = widget.theme;

    final palette = AppPalette.of(context);

    final duration = _duration;

    final totalMs = duration?.inMilliseconds ?? 0;

    final currentMs = totalMs > 0 &&
            widget.active
        ? _position.inMilliseconds
            .clamp(0, totalMs)
            .toDouble()
        : 0.0;

    final fraction = totalMs > 0
        ? currentMs / totalMs
        : 0.0;

    final shownFraction = _dragFraction >= 0
        ? _dragFraction
        : fraction;

    final shownMs = (shownFraction * totalMs)
        .round()
        .clamp(0, totalMs)
        .toDouble();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _cardDecoration(AppPalette.of(context)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [

          // Подпись и время делят строку гибко: при textScale 1.6
          // «Аудиогид» и «00:00 / 06:33» больше не переполняют
          // узкую карточку (A7/B9, 9-й проход).
          Row(
            children: [
              Expanded(child: _label(theme, palette)),
              const SizedBox(width: 8),
              Flexible(
                child: Align(
                  alignment: Alignment.centerRight,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _TimeText(
                          text: formatDuration(
                              Duration(milliseconds: shownMs.round())),
                          style: theme.textTheme.bodySmall,
                        ),
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 4),
                          child: Text('/'),
                        ),
                        _TimeText(
                          text: formatDuration(duration ?? Duration.zero),
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          _Waveform(
            wave: _wave,
            fraction: shownFraction,
            playing: widget.playing,
            semanticsValue: (_duration != null && _duration! > Duration.zero)
                ? '${formatDuration(_position)} из ${formatDuration(_duration!)}'
                : null,
            increasedValue: _skipLabel(_skipSeconds),
            decreasedValue: _skipLabel(-_skipSeconds),
            animation: _waveMotion,
            // Тап — перемотка сразу; перетаскивание — предпросмотр,
            // реальная перемотка один раз, в конце жеста.
            onTapSeek: _seekToFraction,
            onDragChange: (fraction) {

              setState(() {
                _dragFraction = fraction;
              });
            },
            onDragEnd: _finishDrag,
            onDragCancel: _cancelDrag,
            onIncrease: () => _skipBy(_skipSeconds),
            onDecrease: () => _skipBy(-_skipSeconds),
          ),

          const SizedBox(height: 12),

          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [

              _SkipButton(
                tooltip: 'Назад 10 секунд',
                icon: LucideIcons.rotateCcw,
                onPressed: () =>
                    _skipBy(-_skipSeconds),
              ),

              const SizedBox(width: 14),

              _PlayPauseButton(
                playing: widget.playing,
                completed: widget.completed,
                onPressed: () =>
                    _togglePlay(theme),
              ),

              const SizedBox(width: 14),

              _SkipButton(
                tooltip: 'Вперёд 10 секунд',
                icon: LucideIcons.rotateCw,
                onPressed: () =>
                    _skipBy(_skipSeconds),
              ),
            ],
          ),

          const SizedBox(height: 12),

          // Скорость воспроизведения — цикл по тапу (P1-6):
          // 0.75× → 1× → 1.25× → 1.5× → 0.75×. Скорость глобальна:
          // чип слушает ValueNotifier сервиса.
          Center(
            child: ValueListenableBuilder<double>(
              valueListenable: widget.service.speedListenable,
              builder: (context, speed, _) {
                return Semantics(
                  // container держит границу узла: иначе метка
                  // сливается с соседними текстами карточки
                  // (P1-2, 7-й проход).
                  container: true,
                  button: true,
                  label: 'Скорость воспроизведения: ${playbackSpeedLabel(speed)}',
                  child: GestureDetector(
                    onTap: () => widget.onSpeedSelected(
                      _nextSpeed(speed),
                    ),
                    // Тап-цель 44 по высоте — визуальный чип ниже
                    // (P1-2, 7-й проход); opaque — тап по всей зоне.
                    behavior: HitTestBehavior.opaque,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 44),
                      child: Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: palette.sandLight,
                            borderRadius:
                                BorderRadius.circular(AppRadius.pill),
                            border:
                                Border.all(color: palette.sand, width: 1),
                          ),
                          child: Text(
                            playbackSpeedLabel(speed),
                            style: AppText.label.copyWith(
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.4,
                              color: palette.onSurface.withValues(alpha: 0.78),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }


  /// Подпись позиции после ±10 секунд для скринридера:
  /// clamp по границам дорожки, пара к onIncrease/onDecrease.
  String? _skipLabel(double seconds) {
    final duration = _duration;

    if (duration == null || duration <= Duration.zero) {
      return null;
    }

    final maxMs = math.max(0, duration.inMilliseconds - 1);

    final targetMs = (_position.inMilliseconds +
            (seconds * 1000).round())
        .clamp(0, maxMs);

    return '${formatDuration(Duration(milliseconds: targetMs))} '
        'из ${formatDuration(duration)}';
  }


  /// Перематывает к доле дорожки (тап или отпускание после drag).
  Future<void> _seekToFraction(double fraction) async {

    // Не перематываем чужой трек.
    if (!widget.active) {

      return;
    }

    final d = _duration;

    if (d == null) {

      return;
    }

    // Тап по самому концу дорожки тоже не должен упираться
    // ровно в конец файла (см. _skipBy).
    final maxMs = math.max(0, d.inMilliseconds - 1);

    final targetMs =
        (d.inMilliseconds * fraction).round().clamp(0, maxMs);

    await _performSeek(Duration(milliseconds: targetMs));
  }


  /// Перематывает и сразу показывает новую позицию: стрим позиции
  /// молчит, пока трек на паузе/завершён, поэтому цифра обновляется
  /// оптимистично, не дожидаясь события плеера.
  Future<void> _performSeek(Duration target) async {

    if (!mounted) {

      return;
    }

    setState(() {
      _position = target;
    });

    await widget.service.seek(target);

    // Пока seek стоял в очереди сервиса, стрим мог отдать позицию
    // ДО перемотки — фиксируем целевую, чтобы цифра не «отскакивала».
    if (mounted) {

      setState(() {
        _position = target;
      });
    }
  }


  /// Конец перетаскивания: перемотка один раз, в точку отпускания.
  Future<void> _finishDrag() async {

    final fraction = _dragFraction;

    if (fraction >= 0) {

      await _seekToFraction(fraction);
    }

    if (mounted) {

      setState(() {
        _dragFraction = -1;
      });
    }
  }


  /// Жест перехвачен (например, скроллом страницы) — перемотки
  /// не было, просто убираем предпросмотр.
  void _cancelDrag() {

    if (!mounted) {

      return;
    }

    setState(() {
      _dragFraction = -1;
    });
  }

  Widget _label(ThemeData theme, AppPalette palette) {

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [

        Container(
          width: 22,
          height: 22,
          decoration: BoxDecoration(
            color: palette.onSurface,
            shape: BoxShape.circle,
          ),
          child: const Icon(
            LucideIcons.music,
            size: 12,
            color: AppColors.accentOn,
          ),
        ),

        const SizedBox(width: 7),

        // Гибкая подпись: при textScale 1.6 слово сжимается
        // эллипсисом, а не толкает время за край (A7/B9).
        Flexible(
          child: Text(
            'Аудиогид',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppText.label.copyWith(
              color: palette.onSurface,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.7,
            ),
          ),
        ),
      ],
    );
  }


  /// В widget-тестах биндинг — тестовый, не WidgetsFlutterBinding:
  /// вечный тикер вечно планирует кадры и подвешивает
  /// pumpAndSettle, поэтому там волна остаётся статичной.
  bool get _canAnimateWave =>
      WidgetsBinding.instance is WidgetsFlutterBinding &&
      MediaQuery.maybeDisableAnimationsOf(context) != true;

  /// Системное Reduce Motion может смениться после initState
  /// (тесты, системные настройки) — синхронизируемся и на
  /// зависимостях (B12).
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    _syncWaveMotion();
  }

  /// Запускает/останавливает «дыхание» волны по playing.
  void _syncWaveMotion() {

    if (!_canAnimateWave) {

      return;
    }

    if (widget.playing) {

      if (!_waveMotion.isAnimating) {

        _waveMotion.repeat();
      }

    } else if (_waveMotion.isAnimating) {

      _waveMotion.stop();
    }
  }


  void _prepare(String assetPath) {

    widget.service.prepare(assetPath);
  }


  Future<void> _skipBy(double seconds) async {

    if (!widget.active) {

      return;
    }

    final duration = _duration;

    if (duration == null) {

      return;
    }

    var targetMs = _position.inMilliseconds +
        (seconds * 1000).round();

    // Не перематываем ровно в конец файла: seek в точку окончания
    // мгновенно переводит плеер в completed (STATE_ENDED на Android,
    // событие ended на web), и трек «завершается» досрочно.
    final maxMs = math.max(0, duration.inMilliseconds - 1);

    targetMs = targetMs.clamp(0, maxMs);

    await _performSeek(Duration(milliseconds: targetMs));
  }


  Future<void> _togglePlay(ThemeData theme) async {

    unawaited(HapticFeedback.lightImpact());

    // Дослушанный трек перезапускается с начала: сервис сам
    // перезагружает источник (stop + setAsset), лишний seek(0)
    // до play перематывал уже мёртвый файл (A8).
    if (widget.completed) {

      try {

        await widget.service.play(widget.assetPath);

      } catch (_) {

        if (!mounted) {

          return;
        }

        showAppSnackBar(context, 'Не удалось воспроизвести аудио');
      }

      return;
    }

    if (widget.playing) {

      await widget.service.pause();

      return;
    }

    try {

      await widget.service.play(widget.assetPath);

    } catch (_) {

      if (!mounted) {

        return;
      }

      showAppSnackBar(context, 'Не удалось воспроизвести аудио');
    }
  }
}


BoxDecoration _cardDecoration(AppPalette palette) {

  return BoxDecoration(
    borderRadius: BorderRadius.circular(AppRadius.card),
    color: palette.surfaceRaised,
    border: Border.all(
      color: palette.sand,
      width: 1,
    ),
    boxShadow: AppShadows.card(palette.onSurface),
  );
}


/// Генерирует детерминированную плавную волну по строке.
///
/// Соседние столбики образуют гладкую огибающую (синусоида +
/// лёгкий шум), поэтому волна выглядит как настоящая звуковая
/// дорожка, а не как «штрих-код» из несвязных случайных столбиков.
List<double> _buildWave(String seed) {

  final rnd = math.Random(seed.hashCode);

  const barCount = 40;

  final phase = rnd.nextDouble() * 2 * math.pi;

  final base = 0.52 + rnd.nextDouble() * 0.1;

  final amplitude = 0.22 + rnd.nextDouble() * 0.15;

  final frequency = 0.9 + rnd.nextDouble() * 0.8;

  return List<double>.generate(
    barCount,
    (i) {

      final smooth =
          base + amplitude * math.sin(i * frequency + phase);

      final noise = (rnd.nextDouble() - 0.5) * 0.12;

      return (smooth + noise).clamp(0.2, 0.95);
    },
  );
}



/// Время с моноширинными цифрами (без скачков ширины).
class _TimeText extends StatelessWidget {

  const _TimeText({
    required this.text,
    required this.style,
  });


  final String text;

  final TextStyle? style;


  @override
  Widget build(BuildContext context) {

    return Text(
      text,
      style: style?.copyWith(
        fontFeatures: const [
          // Моноширинный интервал для цифр.
          FontFeature.tabularFigures(),
        ],
      ),
    );
  }
}


/// Декоративная волна с прогрессом и перемоткой.
class _Waveform extends StatelessWidget {

  const _Waveform({
    required this.wave,
    required this.fraction,
    required this.playing,
    required this.semanticsValue,
    required this.increasedValue,
    required this.decreasedValue,
    required this.animation,
    required this.onTapSeek,
    required this.onDragChange,
    required this.onDragEnd,
    required this.onDragCancel,
    required this.onIncrease,
    required this.onDecrease,
  });


  final List<double> wave;

  final double fraction;

  final bool playing;

  /// Строка позиции для скринридера («01:15 из 02:40», B12).
  /// `null` — длительность ещё не известна: value/increased/
  /// decreased обязаны быть пустыми ОДНОВРЕМЕННО (assert фреймворка).
  final String? semanticsValue;

  /// Подписи для onIncrease/onDecrease (±10 секунд): фреймворк
  /// требует парные value/increasedValue у слайдера (P1-2,
  /// 7-й проход).
  final String? increasedValue;

  final String? decreasedValue;

  /// «Живая» волна: пока тикер идёт, художник перерисовывается
  /// сам через repaint-листенер — без setState на кадр.
  final Animation<double> animation;

  /// Перемотка по тапу (доля дорожки 0..1).
  final ValueChanged<double> onTapSeek;

  /// Предпросмотр во время перетаскивания (доля дорожки 0..1).
  final ValueChanged<double> onDragChange;

  /// Конец перетаскивания — перемотка в точку отпускания.
  final VoidCallback onDragEnd;

  /// Перетаскивание перехвачено другим жестом (скроллом).
  final VoidCallback onDragCancel;

  /// Управление скринридером (TalkBack): ±10 секунд без жестов
  /// (P1-2, 7-й проход) — слайдер без этих колбэков был
  /// неуправляемым для доступности.
  final VoidCallback onIncrease;

  final VoidCallback onDecrease;


  @override
  Widget build(BuildContext context) {

    const playedColor = AppColors.depthDark;

    // Контраст волны: песок на белой карточке давал ≈1.4:1 —
    // неактивная часть почти не читалась. Теперь серо-бирюзовый
    // outline (≈3.6:1), пройденная — глубокая бирюза depthDark (≈7:1).
    const idleColor = AppColors.outline;

    return Semantics(
      label: 'Дорожка аудиогида',
      slider: true,
      // B12: скринридер объявляет позицию во времени, а не
      // сухой процент.
      value: semanticsValue,
      increasedValue: increasedValue,
      decreasedValue: decreasedValue,
      onIncrease: onIncrease,
      onDecrease: onDecrease,
      child: LayoutBuilder(
        builder: (context, constraints) {

          final width = constraints.maxWidth;

          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            // Тап — перемотка сразу, по отпусканию (чтобы нажатие,
            // переходящее в перетаскивание, не давало лишний seek).
            onTapUp: (details) =>
                _tapAt(width, details.localPosition.dx),
            // Перетаскивание — только предпросмотр: реальная
            // перемотка один раз в конце, иначе очередь seek-ов
            // отстаёт от пальца и цифра «залипает».
            onHorizontalDragStart: (details) =>
                _previewAt(width, details.localPosition.dx),
            onHorizontalDragUpdate: (details) =>
                _previewAt(width, details.localPosition.dx),
            onHorizontalDragEnd: (_) => onDragEnd(),
            onHorizontalDragCancel: onDragCancel,
            child: SizedBox(
              height: 56,
              child: CustomPaint(
                size: Size(width, 56),
                painter: _WavePainter(
                  wave: wave,
                  fraction: fraction,
                  playing: playing,
                  animation: animation,
                  playedColor: playedColor,
                  idleColor: idleColor,
                  width: width,
                ),
              ),
            ),
          );
        },
      ),
    );
  }


  void _previewAt(
    double width,
    double dx,
  ) {

    if (width <= 0) {

      return;
    }

    onDragChange((dx / width).clamp(0.0, 1.0));
  }


  void _tapAt(
    double width,
    double dx,
  ) {

    if (width <= 0) {

      return;
    }

    onTapSeek((dx / width).clamp(0.0, 1.0));
  }
}


/// Отрисовщик волны.
class _WavePainter extends CustomPainter {

  _WavePainter({
    required this.wave,
    required this.fraction,
    required this.playing,
    required this.animation,
    required this.playedColor,
    required this.idleColor,
    required this.width,
  }) : super(repaint: animation);


  final List<double> wave;

  final double fraction;

  final bool playing;

  /// Фаза «живой» волны (0..1 за период).
  final Animation<double> animation;

  final Color playedColor;

  final Color idleColor;

  final double width;


  @override
  void paint(
    Canvas canvas,
    Size size,
  ) {

    final barCount = wave.length;

    final gap = 3.0;

    final barWidth = (width - gap * (barCount - 1)) / barCount;

    // Индекс столбика под плейхедом.
    final playheadIndex = (fraction * barCount).round();

    final paint = Paint();

    for (var i = 0; i < barCount; i++) {

      var barHeight =
          wave[i] * size.height;

      // «Живое дыхание»: столбики в окне ±6 от плейхеда
      // плавно колышутся, пока идёт воспроизведение.
      if (playing &&
          (i - playheadIndex).abs() <= 6) {

        final sway = 1 +
            0.14 *
                math.sin(
                  animation.value * 2 * math.pi + i * 0.7,
                );

        barHeight =
            (barHeight * sway).clamp(0.0, size.height);
      }

      final x = i * (barWidth + gap);

      final y = (size.height - barHeight) / 2;

      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(x, y, barWidth, barHeight),
        Radius.circular(barWidth / 2),
      );

      final centerX = x + barWidth / 2;

      final isPlayed = centerX / width <= fraction;

      paint.color = isPlayed
          ? playedColor
          : idleColor;

      canvas.drawRRect(rect, paint);
    }

    // Плейхед — белая точка с тонкой обводкой.
    if (fraction > 0.001 && fraction < 1.0) {

      final playheadX = fraction * width;

      final center = Offset(playheadX, size.height / 2);

      paint.style = PaintingStyle.fill;

      paint.color = AppColors.onScrim;

      canvas.drawCircle(center, 4.5, paint);

      paint.style = PaintingStyle.stroke;

      paint.strokeWidth = 1.2;

      paint.color = playedColor;

      canvas.drawCircle(center, 4.5, paint);
    }
  }


  @override
  bool shouldRepaint(covariant _WavePainter oldDelegate) {

    return oldDelegate.fraction != fraction ||
        oldDelegate.playing != playing ||
        oldDelegate.wave != wave ||
        oldDelegate.playedColor != playedColor ||
        oldDelegate.idleColor != idleColor;
  }
}


/// Стрелка перемотки ±10 секунд: пилюля с подписью «10»
/// (тап-цель ≥ 44×44 — визуальный размер компактный).
class _SkipButton extends StatelessWidget {

  const _SkipButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });


  final String tooltip;

  final IconData icon;

  final VoidCallback onPressed;


  @override
  Widget build(BuildContext context) {

    return Tooltip(
      message: tooltip,
      child: IconButton(
        onPressed: onPressed,
        icon: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18),
            const SizedBox(width: 4),
            const Text('10'),
          ],
        ),
        style: IconButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 13),
          minimumSize: const Size(44, 44),
          backgroundColor: AppPalette.of(context).sandLight,
          foregroundColor: AppPalette.of(context).onSurface,
          side: BorderSide(
              color: AppPalette.of(context).sand, width: 1),
          shape: const StadiumBorder(),
        ),
      ),
    );
  }
}


/// Круглая кнопка play/pause — главная кнопка плеера, 64 px.
class _PlayPauseButton extends StatelessWidget {

  const _PlayPauseButton({
    required this.playing,
    required this.completed,
    required this.onPressed,
  });


  final bool playing;

  /// Дослушан ли трек до конца (tooltip «Слушать снова»).
  final bool completed;

  final VoidCallback onPressed;


  @override
  Widget build(BuildContext context) {

    final tooltip = completed
        ? 'Слушать снова'
        : playing
            ? 'Пауза'
            : 'Слушать';

    return Tooltip(
      message: tooltip,
      child: DecoratedBox(
        // Мягкая «плавающая» тень под кнопкой.
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          boxShadow:
              AppShadows.floating(AppPalette.of(context).onSurface),
        ),
        child: SizedBox(
          width: 64,
          height: 64,
          child: FilledButton(
            onPressed: onPressed,
            style: FilledButton.styleFrom(
              shape: const CircleBorder(),
              padding: EdgeInsets.zero,
              backgroundColor: AppColors.depth,
              foregroundColor: AppColors.accentOn,
            ),
            child: Icon(
              playing
                  ? LucideIcons.pause
                  : LucideIcons.play,
              size: 30,
            ),
          ),
        ),
      ),
    );
  }
}


/// Шкала скоростей плеера (P1-6).
const List<double> kPlaybackSpeeds = [0.75, 1.0, 1.25, 1.5];

/// Подпись скорости для чипа плеера: 0.75× / 1× / 1.25× / 1.5×.
///
/// Без regex: прежний `replaceFirst(RegExp(r'0\$'))` в raw-строке
/// искал литерал «0$», а не конец строки — 1.5× печаталось как
/// «1.50×» (P0-7, 6-й проход).
String playbackSpeedLabel(double speed) {
  if (speed == speed.truncateToDouble()) {
    return '${speed.toStringAsFixed(0)}×';
  }

  var text = speed.toStringAsFixed(2);

  while (text.endsWith('0')) {
    text = text.substring(0, text.length - 1);
  }

  return '$text×';
}

double _nextSpeed(double current) {
  final index = kPlaybackSpeeds.indexOf(current);

  if (index < 0) {
    return 1.0;
  }

  return kPlaybackSpeeds[(index + 1) % kPlaybackSpeeds.length];
}
