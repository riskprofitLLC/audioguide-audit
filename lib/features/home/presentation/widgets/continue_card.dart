import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:just_audio/just_audio.dart';

import '../../../../app/theme.dart';
import '../../../../core/widgets/app_snack_bar.dart';
import '../../../../core/widgets/skeleton.dart';
import '../../../audio/providers/audio_player_provider.dart';
import '../../../content/models/region_catalog.dart';
import '../../../content/providers/content_providers.dart';
import '../../../settings/providers/settings_providers.dart';
import '../../../poi/models/poi.dart';

/// Карточка «Продолжить» (B2.1, 8-й проход): последний открытый
/// POI с аудио — миниатюра, название, прогресс и кнопка Play.
///
/// Нет истории — блока нет вовсе (тихо). Тап — на страницу точки
/// (плеер там); кнопка Play — сразу запускает трек (сервис
/// продолжает с сохранённой позиции).
class ContinueCard extends ConsumerStatefulWidget {
  const ContinueCard({super.key});

  @override
  ConsumerState<ContinueCard> createState() => _ContinueCardState();
}

class _ContinueCardState extends ConsumerState<ContinueCard> {
  String? _currentFile;

  bool _playing = false;

  bool _completed = false;

  StreamSubscription<PlayerState>? _stateSub;

  StreamSubscription<String?>? _fileSub;

  @override
  void initState() {
    super.initState();

    final service = ref.read(audioPlayerServiceProvider);

    // Провайдер отдаёт один и тот же объект — на смену
    // play/pause/файла подписываемся стримами (A2, 9-й проход):
    // раньше иконка карточки не реагировала на плеер.
    _currentFile = service.currentFile;

    _playing = service.isPlaying && !service.isCompleted;

    _completed = service.isCompleted;

    _stateSub = service.playerStateStream.listen((state) {
      if (!mounted) return;

      setState(() {
        _playing = state.playing;

        _completed = state.processingState == ProcessingState.completed;
      });
    });

    _fileSub = service.currentFileStream.listen((file) {
      if (!mounted) return;

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

  /// Пауза — сразу; запуск — с обработкой ошибок (A5, 10-й
  /// проход): сервис делает rethrow, без catch необработанное
  /// исключение рвётся в зону приложения (битый ассет, автоплей-
  /// политика web).
  Future<void> _togglePlay(String audioPath) async {
    final service = ref.read(audioPlayerServiceProvider);

    if (_playing) {
      await service.pause();

      return;
    }

    try {
      await service.play(audioPath);
    } catch (_) {
      if (!mounted) return;

      showAppSnackBar(context, 'Не удалось воспроизвести аудио');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final recents = ref.watch(recentItemsProvider);

    // Б5 (замечание Sonnet): карточка показывает последний
    // открытый POI С АУДИО, а не просто последний POI — раньше
    // «Продолжить» исчезало, если последняя открытая точка
    // оказывалась без аудио, хотя раньше слушали другую.
    // Идём по истории от свежих к старым; локация в загрузке —
    // скелетон (UI не прыгает), ошибки и точки без аудио —
    // пропускаем.
    Widget? content;

    for (final raw in recents) {
      if (!raw.startsWith('poi:')) {
        continue;
      }

      final parts = raw.split(':');

      if (parts.length != 3) {
        continue;
      }

      final locationId = parts[1];

      final poiId = parts[2];

      final poisAsync = ref.watch(poisFamily(locationId));

      // Локация грузится — не блокируем поиск: до ответа
      // показываем скелетон первого кандидата.
      if (poisAsync.isLoading) {
        content ??= const _ContinueSkeleton();

        continue;
      }

      final pois = poisAsync.value;

      // Ошибка локации/битый ключ — идём дальше по истории.
      if (pois == null) {
        continue;
      }

      final Poi? poi =
          pois.where((p) => p.id == poiId).firstOrNull;

      // Точки без аудио «продолжать» нечего — пропускаем.
      if (poi == null || poi.audioPath == null) {
        continue;
      }

      content = _buildCard(
        theme: theme,
        poi: poi,
        locationId: locationId,
      );

      break;
    }

    if (content == null) {
      return const SizedBox.shrink();
    }

    return content;
  }

  /// Карточка найденного POI с аудио.
  Widget _buildCard({
    required ThemeData theme,
    required Poi poi,
    required String locationId,
  }) {
    final audioPath = poi.audioAssetPath(locationId);

    // Играет ли этот файл сейчас — из живых стримов, а не из
    // замершего снапшота сервиса (A2).
    final isCurrent = _currentFile == audioPath;

    final isPlaying = isCurrent && _playing && !_completed;

    return Padding(
      key: const ValueKey('home-continue-card'),
      // Верхний отступ вместо нижнего: блоки карты («Продолжить»,
      // «Прослушано») управляют зазорами сверху — при скрытии
      // любого из них зазор до соседа не прыгает.
      padding: const EdgeInsets.only(top: AppSpace.m),
      child: Material(
        color: AppPalette.of(context).surfaceRaised,
        borderRadius: BorderRadius.circular(AppRadius.tile),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.tile),
          onTap: () => context.push(
            '/poi/${poi.id}?island=$locationId',
          ),
          child: Container(
            height: 72,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadius.tile),
              border: Border.all(
                  color: AppPalette.of(context).sand, width: 1),
              boxShadow:
                  AppShadows.card(AppPalette.of(context).onSurface),
            ),
            child: Row(
              children: [
                // Миниатюра POI (или глиф-заглушка).
                _ContinueThumb(poi: poi, locationId: locationId),

                const SizedBox(width: 12),

                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Продолжить',
                        // Токен D4.
                        style: AppText.eyebrowMuted.copyWith(
                          color: AppPalette.of(context).info,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        poi.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.body.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(width: 8),

                // Play/Pause: тап запускает трек; карточка остаётся
                // ссылкой на страницу точки.
                _ContinuePlayButton(
                  playing: isPlaying,
                  onTap: () => _togglePlay(audioPath),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Скелетон карточки «Продолжить» (Б5): пока грузится локация
/// свежего кандидата, на главной стоит карточка той же высоты,
/// а не пустота.
class _ContinueSkeleton extends StatelessWidget {
  const _ContinueSkeleton();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.only(top: AppSpace.m),
      child: SkeletonBox(
        height: 72,
        radius: AppRadius.tile,
      ),
    );
  }
}

/// Миниатюра карточки «Продолжить»: фото POI или глиф категории.
class _ContinueThumb extends StatelessWidget {
  const _ContinueThumb({required this.poi, required this.locationId});

  final Poi poi;

  final String locationId;

  @override
  Widget build(BuildContext context) {
    final imagePath = poi.imagePaths.isEmpty
        ? null
        : '${locationAssetBase(locationId)}/images/${poi.imagePaths.first}';

    if (imagePath == null) {
      return Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: AppPalette.of(context).sandLight,
          borderRadius: BorderRadius.circular(AppRadius.thumb),
        ),
        child: const Icon(
          LucideIcons.mapPin,
          size: 20,
          color: AppColors.depth,
        ),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.thumb),
      child: Image.asset(
        imagePath,
        width: 48,
        height: 48,
        fit: BoxFit.cover,
        // B4 (10-й проход): без прыжков раскладки — скелетон
        // до первого кадра. Явная коробка миниатюры (size):
        // из Row приходят неограниченные констрейнты по ширине —
        // Stack с expand обязан получить конечную геометрию.
        frameBuilder: (context, child, frame, wasSynchronouslyLoaded) =>
            skeletonFrameBuilder(
          context,
          child,
          frame,
          wasSynchronouslyLoaded,
          radius: AppRadius.thumb,
          size: 48,
        ),
        errorBuilder: (_, _, _) => Container(
          width: 48,
          height: 48,
          color: AppPalette.of(context).sandLight,
          child: const Icon(
            LucideIcons.mapPin,
            size: 20,
            color: AppColors.depth,
          ),
        ),
      ),
    );
  }
}

class _ContinuePlayButton extends StatelessWidget {
  const _ContinuePlayButton({required this.playing, required this.onTap});

  final bool playing;

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: playing ? 'Пауза' : 'Продолжить прослушивание',
      child: SizedBox(
        width: 44,
        height: 44,
        child: IconButton(
          padding: EdgeInsets.zero,
          onPressed: onTap,
          style: IconButton.styleFrom(
            backgroundColor: AppColors.depth,
            foregroundColor: AppColors.accentOn,
            shape: const CircleBorder(),
          ),
          icon: Icon(
            playing ? LucideIcons.pause : LucideIcons.play,
            size: 20,
          ),
        ),
      ),
    );
  }
}
