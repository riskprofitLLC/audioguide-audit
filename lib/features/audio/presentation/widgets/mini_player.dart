import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';

import '../../../../app/navigation/navigation_shell.dart';
import '../../../../app/overlay_tracker.dart';
import '../../../../app/theme.dart';
import '../../../../app/router.dart' show AppRouter;
import '../../../content/providers/content_providers.dart';
import '../../providers/audio_player_provider.dart';
import 'now_playing_sheet.dart';
import 'track_state.dart';
import '../../../poi/models/poi.dart';

/// Находится ли адрес на странице «своего» POI пилюли (P0-5,
/// 6-й проход).
///
/// id точек повторяются между локациями: на /poi/poi-01?island=bay
/// при играющем gemiler/poi-01 пилюля раньше пряталась зря — путь
/// совпадал по id. Теперь сверяются и путь, и локация
/// (параметр ?island=; без него — текущая локация приложения,
/// как её читает PoiDetailPage).
bool isOnOwnPoiPage(
  Uri route, {
  required String poiId,
  required String locationId,
  required String fallbackIslandId,
}) {
  if (route.path != '/poi/$poiId') {
    return false;
  }

  final island = route.queryParameters['island'] ?? fallbackIslandId;

  return island == locationId;
}

/// Плавающий мини-плеер у нижней кромки экрана.
///
/// Показывается, когда трек аудиогида загружен (играет или на
/// паузе, A3), а пользователь ушёл со страницы этого POI
/// (карта, автогид, другая точка). Тап по пилюле открывает
/// шторку «Сейчас играет»; кнопка справа — пауза/продолжение,
/// крестик — остановка. Пока открыта модальная шторка
/// (POI/маршрут/дерево/легенда), пилюля скрывается — плеер
/// шторки не дублируется поверх неё.
///
/// Слежение за «чем играем» — чистый UI-слой: путь ассета парсится
/// на регион/локацию, POI находится по совпадению
/// `Poi.audioAssetPath` с текущим файлом плеера. Логика сервиса и
/// провайдеров не меняется.
class MiniPlayerOverlay extends ConsumerStatefulWidget {
  const MiniPlayerOverlay({super.key});

  @override
  ConsumerState<MiniPlayerOverlay> createState() => _MiniPlayerOverlayState();
}

class _MiniPlayerOverlayState extends ConsumerState<MiniPlayerOverlay> {
  bool _playing = false;

  late final TrackStateWatcher _track;

  /// Локация + POI играющего трека (резолв по пути ассета).
  (String, String)? _poiRef;

  @override
  void initState() {
    super.initState();

    // Общее отслеживание состояния трека (баг 5/D2): файл,
    // playing/пауза — одним вотчером для мини-плеера и липкой
    // панели POI.
    _track = TrackStateWatcher(
      service: ref.read(audioPlayerServiceProvider),
      onUpdate: _onTrackChanged,
    );

    _playing = _track.playing;

    // Смена маршрута (уход/возврат на страницу своего POI) меняет
    // видимость пилюли; слушатель — вне build, чтобы не дёргать
    // деревo из фазы сборки.
    AppRouter.router.routerDelegate.addListener(_onRouteChanged);

    modalSheetOpenCount.addListener(_onRouteChanged);
  }

  void _onTrackChanged() {
    if (!mounted) {
      return;
    }

    _playing = _track.playing;

    setState(() {
      _poiRef = null;
    });

    _updateVisibility();
  }

  @override
  void dispose() {
    AppRouter.router.routerDelegate.removeListener(_onRouteChanged);

    modalSheetOpenCount.removeListener(_onRouteChanged);

    miniPlayerVisible.value = false;

    _track.dispose();

    super.dispose();
  }

  void _onRouteChanged() {
    if (!mounted) return;

    // POI «своей» страницы резолвится лениво — на смене роута
    // достаточно пересчитать видимость по уже известному _poiRef.
    setState(() {});

    _updateVisibility();
  }

  /// Публикует видимость пилюли в [miniPlayerVisible]: контролы
  /// карты поднимаются над ней (A2c). «Своя» страница
  /// проверяется по пути И локации POI (P0-5).
  void _updateVisibility() {
    var visible = false;

    final file = _track.currentFile;

    // Пилюля живёт, пока файл загружен — и на паузе тоже (A3,
    // 9-й проход): иначе трек, отпущенный со страницы точки и
    // поставленный на паузу, терялся бы без шанса вернуться.
    if (file != null && modalSheetOpenCount.value == 0) {
      final poiRef = _resolvePlayingPoi();

      if (poiRef != null) {
        _poiRef ??= poiRef;

        final route =
            AppRouter.router.routerDelegate.currentConfiguration.uri;

        visible = !isOnOwnPoiPage(
          route,
          poiId: poiRef.$2,
          locationId: poiRef.$1,
          fallbackIslandId: ref.read(currentIslandIdProvider),
        );
      }
    }

    if (miniPlayerVisible.value != visible) {
      miniPlayerVisible.value = visible;
    }
  }

  /// Планирует пересчёт видимости ПОСЛЕ кадра: менять ValueNotifier
  /// из build нельзя — контролы карты уже построены в этом кадре.
  void _scheduleVisibilityUpdate() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _updateVisibility();
    });
  }

  /// Локация из пути ассета: `content/<регион>/<локация>/audio/…`.
  String? get _locationId {
    final file = _track.currentFile;

    if (file == null) return null;

    final parts = file.split('/');

    if (parts.length < 5 || parts.first != 'content') return null;

    return parts[2];
  }

  (String, String)? _resolvePlayingPoi() {
    final locationId = _locationId;

    final file = _track.currentFile;

    if (locationId == null || file == null) return null;

    final pois = ref
            .read(poisFamily(locationId))
            .value ??
        const <Poi>[];

    for (final poi in pois) {
      if (poi.audioPath != null && poi.audioAssetPath(locationId) == file) {
        return (locationId, poi.id);
      }
    }

    return null;
  }

  @override
  Widget build(BuildContext context) {
    final file = _track.currentFile;

    if (file == null || modalSheetOpenCount.value > 0) {
      return const SizedBox.shrink();
    }

    // Подписка на данные локации играющего файла: пока они не
    // загружены, POI не резолвится — раньше ref.read молчал до
    // первого стороннего rebuild, и пилюля не появлялась
    // (P0-5, 6-й проход).
    final fileLocationId = _locationId;

    if (fileLocationId != null) {
      ref.watch(poisFamily(fileLocationId));
    }

    // POI играющего трека резолвится здесь (кеш провайдера уже
    // согрет на странице, откуда трек запущен).
    _poiRef ??= _resolvePlayingPoi();

    if (_poiRef == null) {
      _scheduleVisibilityUpdate();

      return const SizedBox.shrink();
    }

    final route = AppRouter.router.routerDelegate.currentConfiguration.uri;

    final (locationId, poiId) = _poiRef!;

    // На странице своего POI полный плеер уже на экране
    // (путь + локация, P0-5).
    if (isOnOwnPoiPage(
      route,
      poiId: poiId,
      locationId: locationId,
      fallbackIslandId: ref.watch(currentIslandIdProvider),
    )) {
      _scheduleVisibilityUpdate();

      return const SizedBox.shrink();
    }

    _scheduleVisibilityUpdate();

    return _buildPill(context, poiId, locationId);
  }

  Widget _buildPill(
    BuildContext context,
    String poiId,
    String locationId,
  ) {
    final palette = AppPalette.of(context);

    final bottomInset = MediaQuery.paddingOf(context).bottom;

    final width = MediaQuery.sizeOf(context).width;

    // В шелле снизу парит капсула навигации — мини-плеер встаёт
    // над ней. На страницах деталей капсулы нет, зато справа
    // внизу парит HomeButton (52 px, right:12) — пилюля
    // прижимается влево, чтобы его не перекрывать (A2c).
    final inShell = width < 600;

    return Positioned(
      key: const ValueKey('mini-player-pill'),
      left: 16,
      right: inShell ? 16 : 76,
      bottom: (inShell ? NavigationShell.capsuleExtent + 10 : 12) +
          bottomInset,
      child: Center(
        // PointerInterceptor: на web пилюля лежит над
        // платформенным канвасом карты и обязана перехватывать
        // тапы себе, а не в холст (как капсула в navigation_shell,
        // P0-5, 6-й проход).
        child: PointerInterceptor(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            // D3: фон/цвета — из палитры темы (ночная тема не
            // рвётся белой пилюлей).
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppRadius.pill),
                boxShadow: AppShadows.floating(
                    AppPalette.of(context).onSurface),
              ),
              child: Material(
                color: AppPalette.of(context)
                    .surfaceRaised
                    .withValues(alpha: 0.97),
                elevation: 0,
                borderRadius: BorderRadius.circular(AppRadius.pill),
                clipBehavior: Clip.antiAlias,
                child: GestureDetector(
                  // Свайп вниз по пилюле — остановка (B5.3):
                  // тап открывает шторку «Сейчас играет» (B5.2),
                  // навигация на страницу точки — из шторки.
                  onVerticalDragEnd: (details) {
                    if (details.primaryVelocity != null &&
                        details.primaryVelocity! > 250) {
                      _stop();
                    }
                  },
                  child: InkWell(
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                  // Б1: пилюля живёт в builder НАД Navigator'ом —
                  // шторка открывается через контекст root-навигатора.
                  onTap: () => showNowPlayingSheet(
                    AppRouter.rootNavigatorContext ?? context,
                  ),
                  child: Stack(
                    children: [
                      Padding(
                        padding:
                            const EdgeInsets.fromLTRB(10, 6, 6, 9),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 34,
                              height: 34,
                              decoration: BoxDecoration(
                                color: palette.info,
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                LucideIcons.audioLines,
                                size: 16,
                                color: palette.accentOn,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Flexible(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    'Аудиогид',
                                    // Токен D4 вместо повторяющихся copyWith.
                                    style: AppText.eyebrowMuted
                                        .copyWith(color: palette.info),
                                  ),
                                  Text(
                                    _titleOf(poiId, locationId),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelMedium
                                        ?.copyWith(
                                          fontWeight: FontWeight.w800,
                                          color: palette.onSurface,
                                        ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 10),
                            // Tooltip вне Overlay падает («No Overlay widget
                            // found») — пилюля строится в builder поверх
                            // Navigator'а. Кнопка помечается Semantics.
                            Semantics(
                              button: true,
                              label: _playing ? 'Пауза' : 'Слушать',
                              child: IconButton(
                                onPressed: _toggle,
                                icon: Icon(
                                  _playing
                                      ? LucideIcons.pause
                                      : LucideIcons.play,
                                  size: 18,
                                  color: palette.onSurface,
                                ),
                                style: IconButton.styleFrom(
                                  backgroundColor: palette.sandLight,
                                  minimumSize: const Size(44, 44),
                                  padding: EdgeInsets.zero,
                                ),
                              ),
                            ),

                            // Остановка трека, не заходя на страницу
                            // POI (B5.3): крестик, тап-цель 44.
                            Semantics(
                              button: true,
                              label: 'Остановить аудиогид',
                              child: IconButton(
                                onPressed: _stop,
                                icon: Icon(
                                  LucideIcons.x,
                                  size: 18,
                                  color: palette.onSurface,
                                ),
                                style: IconButton.styleFrom(
                                  backgroundColor: palette.sandLight,
                                  minimumSize: const Size(44, 44),
                                  padding: EdgeInsets.zero,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                      // Тонкая линия прогресса по нижней кромке (A2d).
                      const Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: _PillProgressStrip(),
                      ),
                    ],
                  ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _titleOf(String poiId, String locationId) {
    final pois = ref
            .read(poisFamily(locationId))
            .value ??
        const <Poi>[];

    for (final poi in pois) {
      if (poi.id == poiId) return poi.title;
    }

    return '';
  }

  /// Пауза — сразу; продолжение — с обработкой ошибок (A5,
  /// 10-й проход): сервис делает rethrow — без catch необработанное
  /// исключение рвётся в зону приложения (битый ассет, автоплей-
  /// политика web). Общий хелпер с липкой панелью POI (D2).
  Future<void> _toggle() {
    final file = _track.currentFile;

    if (file == null) return Future.value();

    return toggleTrackPlayback(
      context,
      ref,
      playing: _playing,
      assetPath: file,
    );
  }

  /// Останавливает трек и прячет пилюлю (B5.3): без остановки
  /// трека нельзя было закрыть, не открыв страницу POI.
  void _stop() {
    ref.read(audioPlayerServiceProvider).stop();

    setState(() {
      _playing = false;
    });

    _updateVisibility();
  }
}

/// Линия прогресса играющего трека — сигнальная полоска внизу
/// пилюли. Позиция берётся из стримов UI-слоя, сервис не меняется.
class _PillProgressStrip extends ConsumerStatefulWidget {
  const _PillProgressStrip();

  @override
  ConsumerState<_PillProgressStrip> createState() =>
      _PillProgressStripState();
}

class _PillProgressStripState extends ConsumerState<_PillProgressStrip> {
  late final TrackStateWatcher _track;

  @override
  void initState() {
    super.initState();

    _track = TrackStateWatcher(
      service: ref.read(audioPlayerServiceProvider),
      onUpdate: () {
        if (mounted) {
          setState(() {});
        }
      },
    );
  }

  @override
  void dispose() {
    _track.dispose();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final position = _track.position;

    final duration = _track.duration;

    var fraction = 0.0;

    if (position != null && duration != null && duration > Duration.zero) {
      fraction =
          (position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0);
    }

    final palette = AppPalette.of(context);

    return SizedBox(
      height: 3,
      child: LinearProgressIndicator(
        // Всегда детерминированная: 0 — пустая кромка. Индетерминант
        // бегает бесконечно и под FakeAsync не даёт settle завершиться.
        value: fraction,
        minHeight: 3,
        backgroundColor: palette.sand.withValues(alpha: 0.6),
        valueColor: AlwaysStoppedAnimation<Color>(palette.accent),
      ),
    );
  }
}
