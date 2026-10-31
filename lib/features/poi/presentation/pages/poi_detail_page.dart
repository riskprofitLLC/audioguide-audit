import 'package:flutter/foundation.dart';
import '../../../../core/utils/format.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:share_plus/share_plus.dart';
import '../../../../core/widgets.dart';

import '../../../../app/theme.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/utils/back_home.dart';
import '../../../../core/utils/logger.dart';
import '../../../../features/poi/models/poi.dart';
import 'package:island_guide/features/content/services/markdown_blocks.dart';
import '../../../../features/poi/utils/poi_category.dart';
import '../../../../features/favorites/providers/favorites_providers.dart';
import '../../../../features/audio/presentation/widgets/audio_guide_player.dart';
import '../../../../features/audio/presentation/widgets/track_state.dart';
import '../../../../features/audio/providers/audio_player_provider.dart';
import '../../../../features/content/presentation/widgets/image_gallery.dart';
import 'package:island_guide/features/content/presentation/widgets/quiz_card.dart';
import '../../../../features/content/providers/content_providers.dart';
import '../../../../features/settings/providers/settings_providers.dart';
import '../../../../features/settings/providers/listened_providers.dart';
import '../../../../features/weather/providers/weather_providers.dart';
import '../../../../features/map/presentation/widgets/map_controls_hover_lock.dart';
import '../../../../features/map/presentation/widgets/map_preview.dart';
import '../../../../features/map/presentation/widgets/weather_sheet.dart';
import '../../../../features/favorites/presentation/widgets/favorite_button.dart';
import 'package:island_guide/features/favorites/presentation/widgets/collections_rail.dart';
import '../../../../features/navigation/presentation/tree_navigation_button.dart';
import '../../../../features/navigation/presentation/tree_navigation_sheet.dart';


/// Страница точки интереса.
///
/// Открывается по `/poi/:id` (с опциональным параметром
/// `island`), загружает данные из офлайн-пакета острова.
/// Фото-галерея разворачивается во всю ширину экрана
/// (edge-to-edge, под статус-баром) и плавно «плывёт» при
/// прокрутке — параллакс.
///
/// Уход со страницы (назад, свайп, другой маршрут) НЕ
/// останавливает трек этой точки (A3, 9-й проход): мини-плеер
/// подхватывает его на любом экране. Остановка — только явная:
/// крестик/свайп мини-плеера, шторка «Сейчас играет» или
/// закрытие шторки POI на карте.
class PoiDetailPage extends ConsumerStatefulWidget {
  const PoiDetailPage({
    super.key,
    required this.poiId,
    this.islandId,
    this.heroFromFavorites = false,
  });

  final String poiId;
  final String? islandId;

  /// Открыта ли страница из списка ИЗБРАННОГО: hero-полёт кадра
  /// подхватывает тег ветки избранного 'fav-poi-image-…' — теги
  /// главной и избранного уникальны, обе страницы живут в
  /// стеке веток шелла (P1-4, 6-й проход).
  final bool heroFromFavorites;

  @override
  ConsumerState<PoiDetailPage> createState() => _PoiDetailPageState();
}

class _PoiDetailPageState extends ConsumerState<PoiDetailPage> {
  bool _showAppBarTitle = false;

  /// Позиция прокрутки для параллакса hero-галереи.
  final ValueNotifier<double> _scrollOffset = ValueNotifier(0);

  /// Ключ плеера в статье (D5): по нему липкая панель узнаёт,
  /// что плеер уехал за верхний срез экрана.
  final GlobalKey _playerKey = GlobalKey();

  /// Плеер в статье не виден — внизу плавает панель
  /// play/pause + время.
  bool _playerOffscreen = false;

  /// Позиция плеера в статье: ушёл ли за верх экрана (D5).
  void _evaluatePlayerOffscreen() {
    final ctx = _playerKey.currentContext;

    final box = ctx?.findRenderObject();

    if (ctx == null || box is! RenderBox || !box.attached) {
      if (_playerOffscreen) {
        _playerOffscreen = false;

        if (mounted) setState(() {});
      }

      return;
    }

    final dy = box.localToGlobal(Offset.zero).dy;

    final offscreen = dy + box.size.height < 0;

    if (offscreen != _playerOffscreen) {
      _playerOffscreen = offscreen;

      if (mounted) setState(() {});
    }
  }

  @override
  void initState() {
    super.initState();

    // Недавние для поиска (P1-4): помним последние открытые.
    // Постфрейм: менять провайдер в build-фазе нельзя.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      final island = widget.islandId ?? ref.read(currentIslandIdProvider);

      ref.read(recentItemsProvider.notifier).push(
        'poi:$island:${widget.poiId}',
      );
    });
  }

  @override
  void dispose() {
    // Трек, запущенный на этой странице, НЕ останавливаем (A3,
    // 9-й проход): мини-плеер подхватывает его на любом экране,
    // остановка — только явная (крестик пилюли, шторка «Сейчас
    // играет», закрытие шторки POI на карте).
    _scrollOffset.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final String effectiveIslandId = widget.islandId ?? ref.watch(currentIslandIdProvider);
    final bottomInset = MediaQuery.paddingOf(context).bottom;

    AppLogger.info(
      '[PoiDetailPage] build poiId=${widget.poiId} islandId=${widget.islandId} '
      'effective=$effectiveIslandId',
    );

    final poisAsync = ref.watch(poisFamily(effectiveIslandId));

    // Есть ли у точки фото/видео: «пустой» hero (светлый
    // плейсхолдер) требует ТЁМНЫХ значков статус-бара — светлые
    // на бежевой бумаге не читаются (A6).
    final poi = poisAsync.value
        ?.where((p) => p.id == widget.poiId)
        .firstOrNull;
    final hasHeroMedia =
        poi != null && (poi.imagePaths.isNotEmpty || poi.videoPath != null);

    // На широких экранах галерея стоит в колонке с отступом от
    // кромки — статус-бар всегда над БУМАГОЙ, значки только
    // тёмные (4-й проход). Порог синхронен порогу двух колонок
    // контента (P0-1, 5-й проход).
    final wideScreen = MediaQuery.sizeOf(context).width >= 900;

    // Поверх edge-to-edge hero-фото значки статус-бара светлые,
    // над развёрнутой бумажной шапкой (или светлым плейсхолдером
    // без фото, или широкой раскладкой) — тёмные.
    final overlayStyle = _showAppBarTitle || !hasHeroMedia || wideScreen
        ? const SystemUiOverlayStyle(
            statusBarColor: Colors.transparent,
            statusBarIconBrightness: Brightness.dark,
            statusBarBrightness: Brightness.light,
          )
        : const SystemUiOverlayStyle(
            statusBarColor: Colors.transparent,
            statusBarIconBrightness: Brightness.light,
            statusBarBrightness: Brightness.dark,
          );

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: overlayStyle,
      child: Scaffold(
        body: Stack(
          children: [
            Positioned.fill(
              child: NotificationListener<ScrollNotification>(
                onNotification: (notification) {
                  // Только вертикальный скролл самого списка:
                  // горизонтальный PageView галереи всплывает
                  // сюда же и своим pixels (~390) ломал параллакс
                  // и раскрывал шапку (A1).
                  if (notification.metrics.axis != Axis.vertical ||
                      notification.depth != 0) {
                    return false;
                  }
                  _scrollOffset.value = notification.metrics.pixels;
                  if (notification.metrics.pixels > 100 && !_showAppBarTitle) {
                    setState(() => _showAppBarTitle = true);
                  } else if (notification.metrics.pixels <= 100 && _showAppBarTitle) {
                    setState(() => _showAppBarTitle = false);
                  }

                  // Липкая панель аудио (D5): видимость — по
                  // фактической позиции плеера в статье.
                  _evaluatePlayerOffscreen();

                  return false;
                },
                child: poisAsync.when(
                  loading: () => const DetailSkeleton(),
                  error: (error, stack) => Center(
                    child: ErrorState(
                      onRetry: () =>
                          ref.invalidate(poisFamily(effectiveIslandId)),
                    ),
                  ),
                  data: (pois) {
                    final poi = pois.where((p) => p.id == widget.poiId).firstOrNull;
                    if (poi == null) {
                      return const Center(
                        child: NotFoundState(message: 'Точка не найдена'),
                      );
                    }
                    return _PoiDetailContent(
                      heroFromFavorites: widget.heroFromFavorites,
                      poi: poi,
                      islandId: effectiveIslandId,
                      theme: theme,
                      scrollOffset: _scrollOffset,
                      bottomInset: bottomInset,
                      playerKey: _playerKey,
                    );
                  },
                ),
              ),
            ),
            StickyAppBar(
              showTitle: _showAppBarTitle,
              title: poisAsync.maybeWhen(
                data: (pois) => pois.where((p) => p.id == widget.poiId).firstOrNull?.title ?? '',
                orElse: () => '',
              ),
              onBack: () => goBackOrHome(context),
              onFavorite: () => ref
                  .read(favoritesControllerProvider.notifier)
                  .toggle('$effectiveIslandId/${widget.poiId}'),
              onShare: () => _sharePoi(effectiveIslandId),
              onTree: () => showTreeNavigationSheet(context),
              isFavorite: ref.watch(favoritesControllerProvider)
                  .contains('$effectiveIslandId/${widget.poiId}'),
            ),
            // Липкая панель аудио (D5): плеер статьи ушёл за
            // верх — управление остаётся под пальцем. Слева от
            // HomeButton (right:12): панель кончается на 76.
            if (_playerOffscreen &&
                poi != null &&
                poi.audioPath != null)
              Positioned(
                key: const ValueKey('poi-sticky-audio'),
                bottom: 12 + bottomInset,
                left: 16,
                right: 76,
                child: MapControlsHoverLock(
                  child: _PoiStickyAudioBar(
                    assetPath: poi.audioAssetPath(effectiveIslandId),
                  ),
                ),
              ),
            Positioned(
              bottom: 12 + bottomInset,
              right: 12,
              child: const MapControlsHoverLock(
                child: HomeButton(),
              ),
            ),
            // Плавающие кнопки: только «дерево» (B3.3, 8-й проход) —
            // звезда переехала в ряд действий под заголовком.
            if (!_showAppBarTitle)
              Positioned(
                key: const ValueKey('detail-floating-actions'),
                // Вровень с пилюлей «назад» (topPadding + 8), а не
                // под статус-баром.
                top: MediaQuery.paddingOf(context).top + 8,
                right: 16,
                child: const TreeNavigationButton(),
              ),
          ],
        ),
      ),
    );
  }

  // Название + ссылка: голый poi-XX получателю ничего не сообщает.
  void _sharePoi(String islandId) {
    final title = ref.read(poisFamily(islandId)).maybeWhen(
          data: (pois) =>
              pois.where((p) => p.id == widget.poiId).firstOrNull?.title,
          orElse: () => null,
        );
    final url =
        '${AppConstants.webAppUrl}/#/poi/${widget.poiId}?island=$islandId';
    Share.share('${title ?? 'Достопримечательность'} — аудиогид\n$url');
  }
}

/// Высота видимой части hero-галереи.
const double _heroHeight = 300;

/// Запас высоты gallery-контента для параллакса: внутренний
/// блок выше клипа, поэтому при трансляции не возникает щелей.
const double _heroOverscroll = 150;

/// Полноэкранная hero-галерея с параллаксом.
///
/// Галерея занимает всю ширину и «уходит» под статус-бар;
/// при прокрутке внутренний контент смещается медленнее
/// списка — фото как будто лежит глубже страницы. Трансляция
/// выполняется только внутри этого виджета: остальной экран
/// не перестраивается.
class ParallaxHero extends StatelessWidget {
  const ParallaxHero({
    super.key,
    required this.child,
    required this.scrollOffset,
    this.height = _heroHeight,
    this.overscroll = _heroOverscroll,
    this.bottomRadius = 26,
    this.topRadius = 0,
  });

  final Widget child;

  final ValueListenable<double> scrollOffset;

  final double height;

  final double overscroll;

  final double bottomRadius;

  /// Скругление верхних углов — для десктопного варианта,
  /// когда галерея стоит блоком по центру, а не во всю ширину.
  final double topRadius;

  @override
  Widget build(BuildContext context) {
    final innerHeight = height + overscroll;

    final radius = topRadius > 0
        ? BorderRadius.vertical(
            top: Radius.circular(topRadius),
            bottom: Radius.circular(bottomRadius),
          )
        : BorderRadius.vertical(
            bottom: Radius.circular(bottomRadius),
          );

    return ClipRRect(
      borderRadius: radius,
      child: SizedBox(
        height: height,
        child: Stack(
          fit: StackFit.passthrough,
          children: [
            ValueListenableBuilder<double>(
              valueListenable: scrollOffset,
              builder: (context, offset, child) {
                // В покое показана середина внутреннего блока;
                // при прокрутке контент «плывёт» вниз (медленнее
                // списка), clamp не даёт вылезти щели при оттяжке.
                final dy = (-overscroll / 2 + offset * 0.42)
                    .clamp(-overscroll / 2, 0.0);
                return Transform.translate(
                  offset: Offset(0, dy),
                  child: child,
                );
              },
              child: OverflowBox(
                // Внутренний блок выше клипа — OverflowBox даёт
                // ему жить за пределами констрейнтов, лишнее
                // срезается родительским ClipRRect.
                alignment: Alignment.topCenter,
                minHeight: innerHeight,
                maxHeight: innerHeight,
                child: child,
              ),
            ),

            // Скрим сверху: светлые значки статус-бара и
            // плавающие кнопки читаются поверх любого фото.
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      stops: const [0, 0.45],
                      colors: [
                        AppColors.scrimInk.withValues(alpha: 0.34),
                        AppColors.scrimInk.withValues(alpha: 0),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PoiDetailContent extends ConsumerWidget {
  const _PoiDetailContent({
    required this.poi,
    required this.islandId,
    required this.theme,
    required this.scrollOffset,
    required this.bottomInset,
    this.heroFromFavorites = false,
    this.playerKey,
  });

  final Poi poi;
  final String islandId;
  final ThemeData theme;
  final ValueListenable<double> scrollOffset;
  final double bottomInset;

  /// Открыта ли страница из списка избранного: hero-полёт
  /// подхватывает тег ветки избранного (P1-4, 6-й проход).
  final bool heroFromFavorites;

  /// Ключ плеера в статье (D5: липкая панель аудио).
  final GlobalKey? playerKey;

  /// Тег hero-полёта кадра галереи: из избранного — 'fav-…',
  /// из главной и прочих мест — 'poi-image-…' (P1-4).
  String get _heroGalleryTag => heroFromFavorites
      ? 'fav-poi-image-$islandId-${poi.id}'
      : 'poi-image-$islandId-${poi.id}';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Статья — СТРУКТУРОЙ блоков markdown (B3.4): подзаголовки h3,
    // списки, инлайновая типографика. Фолбэк — прежний текстовый
    // режим по poi.json description.
    final fullBlocksAsync = ref.watch(
      poiFullBlocksProvider((islandId: islandId, poiId: poi.id)),
    );

    final blocks = fullBlocksAsync.value;

    final displayText = poi.description;

    final category = poi.category;

    // Аудио-длительность и время чтения для мета-строки (B3.2):
    // «категория · аудио 6:33 · чтение ~3 мин».
    final audioMs = poi.audioMs;

    final audioLabel = audioMs != null && audioMs > 0
        ? 'аудио ${formatDurationMs(audioMs)}'
        : null;

    final readingLabel = _readingMinutes(displayText);

    // Скролл-события ловит ОДИН NotificationListener на странице
    // (в _PoiDetailPageState): события всплывают от ListView
    // сквозь вложенные виджеты, второй слушатель лишь дублировал
    // setState для заголовка шапки.
    //
    // Телефон: hero-галерея первой и без горизонтальных отступов
    // (edge-to-edge, параллакс), контент с отступами 16 px.
    // Широкий экран (B5): слева sticky-колонка «галерея + карта»,
    // справа — статья (текст ≤ 680 px, 16/1.65) и плеер.
    //
    // Раскладка меряется LayoutBuilder'ом по ДОСТУПНОЙ ширине:
    // жёсткие 440 px при окне 600–900 оставляли статье ~100 px
    // (P0-1, 5-й проход). Две колонки — от 900 px, левая колонка
    // = clamp(доступная * 0.42, 320, 440).
    return LayoutBuilder(
      builder: (context, constraints) {
        final available = constraints.maxWidth;

        final wide = available >= 900;

        final leftWidth = (available * 0.42).clamp(320.0, 440.0);

    void openMap() {
      // Играющий трек не глушим (A3): мини-плеер продолжает
      // звучать на карте.
      context.go('/map?poi=${poi.id}&island=$islandId');
    }

    // Бейджи — над заголовком. Wrap: на средней ширине правой
    // колонки бейджи переносятся на вторую строку, а не
    // переполняют её (B5). Координаты убраны в «Подробнее»
    // с копированием (B3.2).
    final badgesRow = Wrap(
      key: const ValueKey('detail-badges'),
      spacing: 8,
      runSpacing: 6,
      children: [
        if (poi.number != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: AppColors.depth,
              borderRadius: BorderRadius.circular(AppRadius.pill),
            ),
            child: Text(
              '№ ${poi.number}',
              // Токен D4 вместо повторяющегося copyWith.
              style: AppText.badge.copyWith(color: AppColors.accentOn),
            ),
          ),
        if (category != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: AppPalette.of(context).sandLight,
              borderRadius: BorderRadius.circular(AppRadius.pill),
              border: Border.all(color: AppPalette.of(context).sand, width: 1),
            ),
            child: Text(
              // Человекочитаемая категория, а не английский id
              // из poi.json (A4).
              poiCategoryLabel(category),
              style: AppText.caption.copyWith(
                fontWeight: FontWeight.w800,
                letterSpacing: 0.4,
                color: AppPalette.of(context).onSurface.withValues(alpha: 0.72),
              ),
            ),
          ),
      ],
    );

    // Мета-строка (B3.2): категория · аудио · чтение — и
    // «Подробнее» с координатами и их копированием.
    final metaRow = _PoiMetaRow(
      islandId: islandId,
      poiId: poi.id,
      categoryLabel: category != null ? poiCategoryLabel(category) : null,
      audioLabel: audioLabel,
      readingLabel: readingLabel,
      latitude: poi.latitude,
      longitude: poi.longitude,
    );

    final title = Text(
      poi.title,
      style: AppText.headline.copyWith(
        height: 1.16,
      ),
    );

    final articleStyle = AppText.bodyL.copyWith(
    );

    // Квизы из статьи (П6, 12-й проход): блоки :::quiz идут
    // карточками ПОД ExpandableText — интерактив не живёт в
    // TextSpan-потоке.
    final quizzes = blocks == null
        ? const <MdQuiz>[]
        : [for (final block in blocks) if (block is MdQuiz) block];

    // collapsedLines 10 (B3.1): 4 строки на странице, где текст —
    // главное, слишком мало.
    final article = blocks != null && blocks.isNotEmpty
        ? ExpandableText(
            blocks: blocks,
            collapsedLines: 10,
            style: articleStyle,
          )
        : displayText != null
            ? ExpandableText(
                text: displayText,
                collapsedLines: 10,
                style: articleStyle,
              )
            : const SizedBox.shrink();

    final mapPreview = MapPreview(
      onTap: openMap,
      islandId: islandId,
      highlightPoiId: poi.id,
      height: 184,
    );

    // Плеер живёт в списке (не sticky): в конце прокрутки нижний
    // отступ оставляет его выше плавающих кнопок.
    final player = poi.audioPath != null
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AudioGuidePlayer(
                assetPath: poi.audioAssetPath(islandId),
                audioMs: poi.audioMs,
                wave: poi.wave,
              ),
              const SizedBox(height: AppSpace.s),
            ],
          )
        // B9: у точки без аудио блок плеера раньше просто
        // отсутствовал — честная тихая подпись вместо пустоты.
        : Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              'Для этого места нет аудио',
              style: AppText.caption.copyWith(
                letterSpacing: 0.3,
                color: AppPalette.of(context).onSurfaceMuted,
              ),
            ),
          );

    if (wide) {
      final screenHeight = MediaQuery.sizeOf(context).height;

      final galleryHeight = (screenHeight * 0.42).clamp(260.0, 360.0);

      final mapHeight = (screenHeight * 0.3).clamp(180.0, 260.0);

      return Padding(
        padding: EdgeInsets.fromLTRB(16, 16, 16, 12 + bottomInset),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: leftWidth,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Sticky-колонка (B5): галерея-карточка со
                  // скруглением и карта под ней.
                  ImageGallery(
                    imagePaths: poi.imagePaths,
                    videoPath: poi.videoPath,
                    islandId: islandId,
                    height: galleryHeight,
                    borderRadius: 26,
                    heroPlaceholder: true,
                    placeholderGlyph: poiCategoryGlyph(poi.category),
                    placeholderCaption: poi.category != null
                        ? '${poiCategoryLabel(poi.category)} · фото появятся позже'
                        : 'Фото появятся позже',
                    semanticLabel: poi.title,
                    heroTag: _heroGalleryTag,
                    // До 12 кадров в карусели (B3.6): длинные
                    // галереи листаются плохо, остальное — сетка
                    // «Все фото».
                    maxCarouselFrames: 12,
                  ),
                  const SizedBox(height: AppSpace.m),
                  MapPreview(
                    onTap: openMap,
                    islandId: islandId,
                    highlightPoiId: poi.id,
                    height: mapHeight,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 20),
            // Align ослабляет tight-констрейнт Expanded (P0-4, 6-й
            // проход): ConstrainedBox внутри Expanded — мёртвый
            // код, enforce зажимал maxWidth обратно до полной
            // ширины, и на 1600+ px строка текста растягивалась
            // на ~1000 px.
            Expanded(
              child: Align(
                alignment: Alignment.topLeft,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 680),
                  child: ListView(
                    // Верх правой колонки — ниже плавающих кнопок
                    // «дерево»+«избранное» (top: 8, высота ~48):
                    // колонка доходит до правой кромки, и на
                    // 900–1100 px бейджи с заголовком попадали
                    // под кнопки (P0-5, 7-й проход).
                    padding: EdgeInsets.fromLTRB(
                      0,
                      64,
                      0,
                      148 + bottomInset,
                    ),
                    children: [
                      badgesRow,
                      const SizedBox(height: AppSpace.s),
                      title,
                      const SizedBox(height: AppSpace.s),
                      metaRow,
                      const SizedBox(height: AppSpace.m),
                      _PoiActionsRow(
                        poi: poi,
                        islandId: islandId,
                        onListen: () => _playOwnAudio(ref),
                        onOpenMap: openMap,
                      ),
                      const SizedBox(height: AppSpace.m),
                      // Ключ — для липкой панели аудио (D5).
                      KeyedSubtree(key: playerKey, child: player),
                      const SizedBox(height: AppSpace.s),
                      article,
                      for (final quiz in quizzes) ...[
                        const SizedBox(height: AppSpace.m),
                        QuizCard(quiz: quiz),
                      ],
                      const SizedBox(height: AppSpace.l),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    final hero = ParallaxHero(
      scrollOffset: scrollOffset,
      child: ImageGallery(
        imagePaths: poi.imagePaths,
        videoPath: poi.videoPath,
        islandId: islandId,
        height: _heroHeight + _heroOverscroll,
        visibleHeight: _heroHeight,
        borderRadius: 0,
        bordered: false,
        heroPlaceholder: true,
        placeholderGlyph: poiCategoryGlyph(poi.category),
        placeholderCaption: poi.category != null
            ? '${poiCategoryLabel(poi.category)} · фото появятся позже'
            : 'Фото появятся позже',
        semanticLabel: poi.title,
        heroTag: _heroGalleryTag,
        // До 12 кадров в карусели (B3.6): длинные галереи
        // листаются плохо, остальное — сетка «Все фото».
        maxCarouselFrames: 12,
      ),
    );

    return ListView(

        // Нижний отступ больше высоты плавающих кнопок (52 px +
        // bottom: 12 + нижний жест-бар + запас), чтобы в конце
        // прокрутки плеер вставал выше них и не перекрывался.
        padding: EdgeInsets.only(bottom: 148 + bottomInset),

        children: [
          hero,
          ContentColumn(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, AppSpace.l, 20, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  badgesRow,
                  const SizedBox(height: AppSpace.s),
                  title,
                  const SizedBox(height: AppSpace.s),
                  // Мета: категория · аудио · чтение (B3.2).
                  metaRow,
                  const SizedBox(height: AppSpace.m),
                  // Аудио первично (B0): «Слушать» — главный
                  // акцент, плеер — сразу под ним, до карты и
                  // статьи (B3.1).
                  _PoiActionsRow(
                    poi: poi,
                    islandId: islandId,
                    onListen: () => _playOwnAudio(ref),
                    onOpenMap: openMap,
                  ),
                  const SizedBox(height: AppSpace.m),
                  // Ключ — для липкой панели аудио (D5).
                  KeyedSubtree(key: playerKey, child: player),
                  const SizedBox(height: AppSpace.m),
                  mapPreview,
                  if (displayText != null) ...[
                    const SizedBox(height: AppSpace.xl),
                    article,
                  ],
                  for (final quiz in quizzes) ...[
                    const SizedBox(height: AppSpace.m),
                    QuizCard(quiz: quiz),
                  ],
                  const SizedBox(height: AppSpace.l),
                ],
              ),
            ),
          ),
        ],
      );
        },
    );
  }

  /// «Слушать» из ряда действий (B3.3): запускает свой трек.
  /// Сервис сам защищает от повторного запуска звучащего файла.
  Future<void> _playOwnAudio(WidgetRef ref) async {
    if (poi.audioPath == null) {
      return;
    }

    final service = ref.read(audioPlayerServiceProvider);

    try {
      await service.play(poi.audioAssetPath(islandId));
    } catch (error) {
      AppLogger.error(
        'Не удалось запустить аудио ${poi.id}',
        error: error,
      );
    }
  }
}


/// «чтение ~3 мин» по числу слов (180 слов/мин, B3.2).
String? _readingMinutes(String? text) {
  if (text == null || text.isEmpty) {
    return null;
  }

  final words = text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;

  if (words < 30) {
    return null;
  }

  final minutes = (words / 180).round();

  return 'чтение ~${minutes < 1 ? 1 : minutes} мин';
}

/// Мета-строка под заголовком (B3.2): категория · аудио ·
/// чтение, координаты — в раскрывающемся «Подробнее» с
/// копированием в буфер.
class _PoiMetaRow extends ConsumerStatefulWidget {
  const _PoiMetaRow({
    required this.islandId,
    required this.poiId,
    required this.categoryLabel,
    required this.audioLabel,
    required this.readingLabel,
    required this.latitude,
    required this.longitude,
  });

  final String islandId;

  final String poiId;

  final String? categoryLabel;

  final String? audioLabel;

  final String? readingLabel;

  final double latitude;

  final double longitude;

  @override
  ConsumerState<_PoiMetaRow> createState() => _PoiMetaRowState();
}

class _PoiMetaRowState extends ConsumerState<_PoiMetaRow> {
  bool _coordsVisible = false;

  @override
  Widget build(BuildContext context) {
    // «Прослушано» (D5): галочка в чипе аудио, когда точка уже
    // была дослушана до 80%.
    final listened = ref
        .watch(listenedSetProvider)
        .contains('${widget.islandId}/${widget.poiId}');

    final chips = <Widget>[
      if (widget.categoryLabel != null)
        _MetaChip(
          icon: LucideIcons.mapPin,
          label: widget.categoryLabel!,
        ),
      if (widget.audioLabel != null)
        _MetaChip(
          icon: LucideIcons.headphones,
          label: listened
              ? '${widget.audioLabel} · прослушано'
              : widget.audioLabel!,
          // Дослушанная точка — галочка успеха.
          check: listened,
        ),
      if (widget.readingLabel != null)
        _MetaChip(
          icon: LucideIcons.clock,
          label: widget.readingLabel!,
        ),
    ];

    // Нет ни категории, ни аудио, ни времени чтения (A6,
    // 11-й проход) — не рисуем пустой Text: остаётся только
    // кнопка «Подробнее» с координатами.
    final hasMeta = chips.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // D5 (замечание Sonnet): мета — чипами с иконками, а не
        // сплошной строкой: Wrap переносит на textScale 1.6.
        if (hasMeta)
          Wrap(
            spacing: AppSpace.xs,
            runSpacing: 6,
            children: chips,
          ),
        _MoreButton(
          expanded: _coordsVisible,
          onTap: () => setState(() => _coordsVisible = !_coordsVisible),
        ),
        if (_coordsVisible)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: _CoordsRow(
              latitude: widget.latitude,
              longitude: widget.longitude,
            ),
          ),
      ],
    );
  }
}

/// Мета-чип (D5): маленькая песочная пилюля с иконкой и подписью.
class _MetaChip extends StatelessWidget {
  const _MetaChip({
    required this.icon,
    required this.label,
    this.check = false,
  });

  final IconData icon;

  final String label;

  /// Галочка успеха (точка прослушана).
  final bool check;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: palette.sandLight,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: palette.sand, width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            check ? LucideIcons.check : icon,
            size: 13,
            color: check ? palette.success : palette.onSurfaceMuted,
          ),
          const SizedBox(width: 6),
          // textScale 1.6 на узких экранах: длинная подпись чипа
          // обрезается эллипсисом, а не переполняет пилюлю
          // (D3, замечания Sonnet — RenderFlex overflow).
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppText.caption.copyWith(
                fontWeight: FontWeight.w700,
                letterSpacing: 0.3,
                color: palette.onSurfaceMuted,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Кнопка-стрелка «Подробнее» (координаты).
class _MoreButton extends StatelessWidget {
  const _MoreButton({required this.expanded, required this.onTap});

  final bool expanded;

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: expanded ? 'Скрыть координаты' : 'Координаты точки',
      child: SizedBox(
        width: 44,
        height: 44,
        child: IconButton(
          padding: EdgeInsets.zero,
          tooltip: expanded ? 'Скрыть координаты' : 'Координаты точки',
          onPressed: onTap,
          icon: Icon(
            expanded ? LucideIcons.chevronUp : LucideIcons.chevronDown,
            size: 18,
            color: AppPalette.of(context).onSurfaceMuted,
          ),
        ),
      ),
    );
  }
}

/// Строка координат с кнопкой «Скопировать».
class _CoordsRow extends StatelessWidget {
  const _CoordsRow({
    required this.latitude,
    required this.longitude,
  });

  final double latitude;

  final double longitude;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final coords =
        '${latitude.toStringAsFixed(5)}, ${longitude.toStringAsFixed(5)}';

    return Row(
      children: [
        Expanded(
          child: Text(
            coords,
            style: theme.textTheme.bodySmall?.copyWith(
              fontFeatures: const [FontFeature.tabularFigures()],
              color: AppPalette.of(context).onSurfaceMuted,
            ),
          ),
        ),
        TextButton.icon(
          onPressed: () {
            Clipboard.setData(ClipboardData(text: coords));

            showAppSnackBar(context, 'Координаты скопированы');
          },
          icon: const Icon(LucideIcons.copy, size: 14),
          label: const Text('Скопировать'),
        ),
      ],
    );
  }
}

/// Ряд действий точки (B3.3; B5, 9-й проход): «Слушать»
/// (primary), «На карте», «В избранное», «Поделиться» — одной
/// высоты 44, на узком экране переносятся Wrap'ом, а не уезжают
/// за край горизонтальным скроллом (A7).
class _PoiActionsRow extends ConsumerWidget {
  const _PoiActionsRow({
    required this.poi,
    required this.islandId,
    required this.onListen,
    required this.onOpenMap,
  });

  final Poi poi;

  final String islandId;

  final VoidCallback onListen;

  final VoidCallback onOpenMap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasAudio = poi.audioPath != null;

    // Все текстовые кнопки ряда — одной высоты 44 (A7/B5):
    // Material-дефолт 40 ниже тап-цели проекта. standard-плотность
    // компенсирует comfortablePlatformDensity темы, срезающую
    // высоту до 40 на десктопе (IconButton minimumSize её не
    // срезает — высоты в ряду расходились).
    final filledStyle = FilledButton.styleFrom(
      minimumSize: const Size(0, 44),
      visualDensity: VisualDensity.standard,
    );

    final outlinedStyle = OutlinedButton.styleFrom(
      minimumSize: const Size(0, 44),
      visualDensity: VisualDensity.standard,
    );

    return Wrap(
      key: const ValueKey('detail-actions-row'),
      spacing: AppSpace.xs,
      runSpacing: AppSpace.xs,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (hasAudio)
          Semantics(
            button: true,
            label: 'Слушать аудиогид',
            child: FilledButton.icon(
              onPressed: onListen,
              style: filledStyle,
              icon: const Icon(LucideIcons.play, size: 18),
              label: const Text('Слушать'),
            ),
          ),
        Semantics(
          button: true,
          label: 'Показать на карте',
          child: OutlinedButton.icon(
            onPressed: onOpenMap,
            style: outlinedStyle,
            icon: const Icon(LucideIcons.map, size: 16),
            label: const Text('На карте'),
          ),
        ),

        // Погода точки идёт сразу за навигацией: запрос по
        // координатам самой достопримечательности, а не центра
        // локации. Тап — шторка с прогнозом и «Обновить».
        Semantics(
          button: true,
          label: 'Погода в этом месте',
          child: OutlinedButton.icon(
            onPressed: () => _showPoiWeather(context, ref, poi),
            style: outlinedStyle,
            icon: const Icon(LucideIcons.cloudSun, size: 16),
            label: const Text('Погода'),
          ),
        ),
        FavoriteButton(
          itemId: poi.id,
          islandId: islandId,
          compact: true,
        ),
        Semantics(
          button: true,
          label: 'Поделиться',
          child: IconButton(
            tooltip: 'Поделиться',
            onPressed: () => _sharePoi(poi, islandId),
            icon: const Icon(LucideIcons.share2, size: 18),
            style: IconButton.styleFrom(
              backgroundColor: Colors.transparent,
              side: const BorderSide(color: AppColors.brandPrimary, width: 1.5),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.field),
              ),
              minimumSize: const Size(44, 44),
              padding: const EdgeInsets.symmetric(horizontal: 14),
            ),
          ),
        ),

        // В подборку (П8, 12-й проход): шторка выбора коллекции.
        OutlinedButton.icon(
          onPressed: () => showCollectionPicker(
            context,
            itemKey: '$islandId/${poi.id}',
          ),
          style: outlinedStyle,
          icon: const Icon(LucideIcons.listPlus, size: 16),
          label: const Text('В подборку'),
        ),
      ],
    );
  }

  /// Шторка погоды точки: загрузка по координатам POI,
  /// «Обновить» — принудительный перезапрос мимо кеша.
  Future<void> _showPoiWeather(
    BuildContext context,
    WidgetRef ref,
    Poi poi,
  ) {
    return showAppBottomSheet(
      context,
      title: 'Погода в этом месте',
      maxHeightFactor: 0.8,
      builder: (sheetContext) => _PoiWeatherSheetBody(
        latitude: poi.latitude,
        longitude: poi.longitude,
      ),
    );
  }

  /// Ссылка на точку для «Поделиться» (перенос из шапки, B3.3).
  Future<void> _sharePoi(Poi poi, String islandId) async {
    final url =
        '${AppConstants.webAppUrl}/#/poi/${poi.id}?island=$islandId';

    await Share.share('${poi.title} — аудиогид\n$url');
  }
}

/// Тело шторки «Погода в этом месте»: запрос по координатам
/// самой точки. Первый показ берёт кеш (TTL 30 минут), кнопка
/// «Обновить» принудительно перезапрашивает API.
class _PoiWeatherSheetBody extends ConsumerStatefulWidget {
  const _PoiWeatherSheetBody({
    required this.latitude,
    required this.longitude,
  });

  final double latitude;

  final double longitude;

  @override
  ConsumerState<_PoiWeatherSheetBody> createState() =>
      _PoiWeatherSheetBodyState();
}

class _PoiWeatherSheetBodyState extends ConsumerState<_PoiWeatherSheetBody> {
  /// Счётчик обновлений: рост создаёт новый инстанс
  /// [poiWeatherProvider] — перезапрос мимо кеша.
  int _refreshGen = 0;

  @override
  Widget build(BuildContext context) {
    final point = (
      lat: widget.latitude,
      lng: widget.longitude,
      gen: _refreshGen,
    );

    final weatherAsync = ref.watch(poiWeatherProvider(point));

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        weatherAsync.when(
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 12),
                Text('Загружаем погоду…'),
              ],
            ),
          ),
          error: (error, _) => _unavailable(context),
          data: (weather) => weather == null
              ? _unavailable(context)
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    WeatherSheet(weather: weather),
                  ],
                ),
        ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: () => setState(() => _refreshGen++),
            icon: const Icon(LucideIcons.refreshCw, size: 16),
            label: const Text('Обновить'),
          ),
        ),
      ],
    );
  }

  /// Нет сети или API не ответил: погода — онлайн-обогащение.
  Widget _unavailable(BuildContext context) {
    return const StatePlaceholder(
      compact: true,
      icon: LucideIcons.cloudOff,
      title: 'Погода недоступна',
      description:
          'Нужен интернет — данные приходят с сервиса Open-Meteo.',
    );
  }
}

/// Липкая панель аудио страницы POI (D5, замечание Sonnet):
/// когда плеер статьи уехал за верх экрана, управление остаётся
/// под пальцем — play/pause и время на «стеклянной» пилюле.
///
/// Показывается ТОЛЬКО пока звучит (или на паузе) трек ЭТОЙ
/// точки: глобальный мини-плеер на своей странице скрыт, а
/// панель не конкурирует с HomeButton (right:12 — панель
/// кончается на 76).
class _PoiStickyAudioBar extends ConsumerStatefulWidget {
  const _PoiStickyAudioBar({required this.assetPath});

  /// Ассет трека этой точки.
  final String assetPath;

  @override
  ConsumerState<_PoiStickyAudioBar> createState() =>
      _PoiStickyAudioBarState();
}

class _PoiStickyAudioBarState extends ConsumerState<_PoiStickyAudioBar> {
  bool _playing = false;

  Duration? _position;

  Duration? _duration;

  /// Смена файла: панель привязана к треку ЭТОЙ точки (баг 5,
  /// замечания Sonnet) — при старте другого файла она исчезает,
  /// при возврате — появляется снова.
  String? _file;

  late final TrackStateWatcher _track;

  @override
  void initState() {
    super.initState();

    _track = TrackStateWatcher(
      service: ref.read(audioPlayerServiceProvider),
      onUpdate: _onTrackUpdate,
    );

    _syncFromTrack();
  }

  void _onTrackUpdate() {
    if (!mounted) {
      return;
    }

    _syncFromTrack();

    setState(() {});
  }

  void _syncFromTrack() {
    _playing = _track.playing;

    _position = _track.position;

    _duration = _track.duration;

    _file = _track.currentFile;
  }

  @override
  void dispose() {
    _track.dispose();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Точка перестала звучать (стоп/другой трек) — панель тихо
    // исчезает, не перекрывая контент. Живой файл — из вотчера
    // (баг 5): подписка на currentFileStream, а не снапшот.
    if (_file != widget.assetPath) {
      return const SizedBox.shrink();
    }

    final position = _position ?? Duration.zero;

    final duration = _duration;

    final timeLabel = duration == null || duration <= Duration.zero
        ? formatDuration(position)
        : '${formatDuration(position)} / ${formatDuration(duration)}';

    final palette = AppPalette.of(context);

    return FloatingPill(
      tone: FloatingPillTone.info,
      padding: const EdgeInsets.fromLTRB(8, 6, 10, 6),
      leading: Semantics(
        button: true,
        label: _playing ? 'Пауза' : 'Слушать',
        child: IconButton(
          onPressed: () => toggleTrackPlayback(
            context,
            ref,
            playing: _playing,
            assetPath: widget.assetPath,
          ),
          icon: Icon(
            _playing ? LucideIcons.pause : LucideIcons.play,
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
      gap: 8,
      child: Text(
        timeLabel,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w800,
              color: palette.onSurface,
            ),
      ),
    );
  }
}
