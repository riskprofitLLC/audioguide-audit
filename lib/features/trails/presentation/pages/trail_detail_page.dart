import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../app/theme.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/utils/back_home.dart';
import '../../../../core/utils/plural.dart';
import '../../../../core/widgets.dart';
import '../../../../features/trails/models/trail.dart';
import '../../../../features/content/presentation/widgets/image_gallery.dart';
import '../../../../features/content/providers/content_providers.dart';
import '../widgets/boat_badge.dart';
import '../widgets/elevation_profile.dart';
import '../../../../features/settings/providers/settings_providers.dart';
import '../../../../features/map/presentation/widgets/map_controls_hover_lock.dart';
import '../../../../features/map/presentation/widgets/map_preview.dart';
import '../../../../features/favorites/presentation/widgets/favorite_button.dart';
import '../../../../features/navigation/presentation/tree_navigation_button.dart';
import '../../../../features/navigation/presentation/tree_navigation_sheet.dart';
import '../../../../features/poi/models/poi.dart';
import '../../../../features/poi/presentation/widgets/poi_list_tile.dart';
import '../../../../features/poi/utils/poi_sort.dart';
import '../../../../features/favorites/providers/favorites_providers.dart';
import '../../utils/format_distance.dart';
import '../../utils/elevation_stats.dart';
import '../../utils/trail_gallery.dart';
import '../../../poi/presentation/pages/poi_detail_page.dart'
    show ParallaxHero;


/// Страница маршрута.
///
/// Открывается по `/trail/:id` (с опциональным параметром
/// `island`). Показывает галерею во всю ширину (edge-to-edge,
/// параллакс), название, длину, описание и карту с маршрутом.
class TrailDetailPage extends ConsumerStatefulWidget {
  const TrailDetailPage({
    super.key,
    required this.trailId,
    this.islandId,
  });

  final String trailId;
  final String? islandId;

  @override
  ConsumerState<TrailDetailPage> createState() => _TrailDetailPageState();
}

class _TrailDetailPageState extends ConsumerState<TrailDetailPage> {
  bool _showAppBarTitle = false;

  /// Позиция прокрутки для параллакса hero-галереи.
  final ValueNotifier<double> _scrollOffset = ValueNotifier(0);

  @override
  void initState() {
    super.initState();

    // Недавние для поиска (P1-4): помним последние открытые.
    // Постфрейм: менять провайдер в build-фазе нельзя.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      final island = widget.islandId ?? ref.read(currentIslandIdProvider);

      ref.read(recentItemsProvider.notifier).push(
        'trail:$island:${widget.trailId}',
      );
    });
  }

  @override
  void dispose() {
    _scrollOffset.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final String effectiveIslandId = widget.islandId ?? ref.watch(currentIslandIdProvider);
    final bottomInset = MediaQuery.paddingOf(context).bottom;

    final trailsAsync = ref.watch(trailsFamily(effectiveIslandId));
    final poisAsync = ref.watch(poisFamily(effectiveIslandId));

    final trailPoiKeys = <String>[
      for (final poi in poisAsync.value ?? const <Poi>[])
        if (poi.trailIds.contains(widget.trailId))
          '$effectiveIslandId/${poi.id}',
    ];

    final trailPois = sortPoisForDisplay([
      for (final poi in poisAsync.value ?? const <Poi>[])
        if (poi.trailIds.contains(widget.trailId)) poi,
    ]);

    // Кадры галереи — ТОЛЬКО фото точек маршрута (P1-3, 7-й
    // проход): раньше здесь собирались фото всех POI локации —
    // внемаршрутные точки попадали в «галерею маршрута», а
    // обложка (из точек маршрута) не совпадала с первым кадром,
    // и hero-полёт отключался.
    final galleryImages = trailGalleryImages(
      poisAsync.value ?? const <Poi>[],
      widget.trailId,
    );

    // Обложка TrailCard — первый кадр этой же галереи: hero-тег
    // совпадает с первым кадром всегда, когда фото есть.
    final trailHeroTag = galleryImages.isNotEmpty
        ? 'trail-image-$effectiveIslandId-${widget.trailId}'
        : null;

    final galleryVideoPath = <String>[
      for (final poi in trailPois)
        if (poi.videoPath != null) poi.videoPath!,
    ].firstOrNull;

    // Пустой hero (нет фото ни у одной точки маршрута) — светлый
    // плейсхолдер, значки статус-бара нужны тёмные (A6).
    final hasHeroMedia =
        galleryImages.isNotEmpty || galleryVideoPath != null;

    // На широких экранах галерея в колонке с отступом —
    // статус-бар над бумагой, значки только тёмные (4-й проход).
    // Порог синхронен порогу двух колонок контента (P0-1).
    final wideScreen = MediaQuery.sizeOf(context).width >= 900;

    // Поверх edge-to-edge hero-фото значки статус-бара светлые,
    // над развёрнутой бумажной шапкой (или светлым плейсхолдером,
    // или широкой раскладкой) — тёмные.
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
                  return false;
                },
                child: trailsAsync.when(
                  loading: () => const DetailSkeleton(),
                  error: (error, stack) => Center(
                    child: ErrorState(
                      onRetry: () =>
                          ref.invalidate(trailsFamily(effectiveIslandId)),
                    ),
                  ),
                  data: (trails) {
                    final trail = trails.where((t) => t.id == widget.trailId).firstOrNull;
                    if (trail == null) {
                      return const Center(
                        child: NotFoundState(message: 'Маршрут не найден'),
                      );
                    }
                    return _TrailDetailContent(
                      trail: trail,
                      islandId: effectiveIslandId,
                      galleryImages: galleryImages,
                      galleryVideoPath: galleryVideoPath,
                      trailPois: trailPois,
                      poiCount: trailPois.length,
                      heroTag: trailHeroTag,
                      theme: theme,
                      scrollOffset: _scrollOffset,
                      bottomInset: bottomInset,
                    );
                  },
                ),
              ),
            ),
            StickyAppBar(
              showTitle: _showAppBarTitle,
              title: trailsAsync.maybeWhen(
                data: (trails) => trails.where((t) => t.id == widget.trailId).firstOrNull?.name ?? '',
                orElse: () => '',
              ),
              onBack: () => goBackOrHome(context),
              onFavorite: () => ref
                  .read(favoritesControllerProvider.notifier)
                  .toggle('$effectiveIslandId/${widget.trailId}', cascadeKeys: trailPoiKeys),
              onShare: () => _shareTrail(effectiveIslandId),
              onTree: () => showTreeNavigationSheet(context),
              isFavorite: ref.watch(favoritesControllerProvider)
                  .contains('$effectiveIslandId/${widget.trailId}'),
            ),
            Positioned(
              bottom: 12 + bottomInset,
              right: 12,
              child: const MapControlsHoverLock(
                child: HomeButton(),
              ),
            ),
            // Плавающая звезда «в избранное» — только пока шапка
            // скрыта: при прокрутке её занимает кнопка в шапке.
            if (!_showAppBarTitle)
              Positioned(
                key: const ValueKey('detail-floating-actions'),
                // Вровень с пилюлей «назад» (topPadding + 8), а не
                // под статус-баром.
                top: MediaQuery.paddingOf(context).top + 8,
                right: 16,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const TreeNavigationButton(),
                    const SizedBox(width: 8),
                    FavoriteButton(
                      itemId: widget.trailId,
                      islandId: effectiveIslandId,
                      cascadeKeys: trailPoiKeys,
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  // Название + ссылка: голой trail-XX получателю ничего не сообщает.
  void _shareTrail(String islandId) {
    final name = ref.read(trailsFamily(islandId)).maybeWhen(
          data: (trails) =>
              trails.where((t) => t.id == widget.trailId).firstOrNull?.name,
          orElse: () => null,
        );
    final url =
        '${AppConstants.webAppUrl}/#/trail/${widget.trailId}?island=$islandId';
    Share.share('${name ?? 'Маршрут'} — аудиогид\n$url');
  }
}

class _TrailDetailContent extends ConsumerWidget {
  const _TrailDetailContent({
    required this.trail,
    required this.islandId,
    required this.galleryImages,
    this.galleryVideoPath,
    required this.trailPois,
    required this.poiCount,
    this.heroTag,
    required this.theme,
    required this.scrollOffset,
    required this.bottomInset,
  });

  final Trail trail;
  final String islandId;
  final List<String> galleryImages;
  final String? galleryVideoPath;

  /// Точки маршрута в порядке номеров — список на странице
  /// (раньше страница не показывала своих точек вообще: под
  /// описанием оставалась пустота).
  final List<Poi> trailPois;

  final int poiCount;

  /// Тег Hero обложки (совпадение кадра с обложкой проверено
  /// выше, см. _TrailDetailPageState).
  final String? heroTag;
  final ThemeData theme;
  final ValueListenable<double> scrollOffset;
  final double bottomInset;

  /// Секция «Точки маршрута»: плитки-точки в порядке номеров.
  ///
  /// Hero-тег не передаём: теги плиток главной (`poi-image-…`)
  /// живут в соседней ветке IndexedStack — одинаковые теги дают
  /// «multiple heroes share the same tag» при push.
  Widget _pointsSection(WidgetRef ref, Set<String> favorites) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionTitle(title: 'Точки маршрута', count: trailPois.length),
        const SizedBox(height: AppSpace.xs),
        for (var i = 0; i < trailPois.length; i++)
          PoiListTile(
            key: ValueKey('trail-point-${trailPois[i].id}'),
            poi: trailPois[i],
            islandId: islandId,
            showDivider: i < trailPois.length - 1,
            isFavorite: favorites.contains('$islandId/${trailPois[i].id}'),
            onFavoriteToggle: () => ref
                .read(favoritesControllerProvider.notifier)
                .toggle('$islandId/${trailPois[i].id}'),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final favorites = ref.watch(favoritesControllerProvider);

    // Скролл-события ловит ОДИН NotificationListener на странице
    // (_TrailDetailPageState): события всплывают от ListView сквозь
    // вложенные виджеты, второй слушатель лишь дублировал setState.
    //
    // Телефон: hero edge-to-edge с параллаксом, затем контент.
    // Широкий экран (B5): слева sticky-колонка «галерея + карта»,
    // справа — бейджи, заголовок и описание.
    //
    // Раскладка меряется LayoutBuilder'ом по ДОСТУПНОЙ ширине
    // (P0-1, 5-й проход): две колонки — от 900 px, левая =
    // clamp(доступная * 0.42, 320, 440).
    return LayoutBuilder(
      builder: (context, constraints) {
        final available = constraints.maxWidth;

        final wide = available >= 900;

        final leftWidth = (available * 0.42).clamp(320.0, 440.0);

    void openMap() {
      context.go('/map?island=$islandId&trail=${trail.id}');
    }

    // Морская локация (П3): маршрут осматривается с воды.
    final isBoat =
        ref.watch(islandManifestFamily(islandId)).value?.isBoat ?? false;

    final badgesRow = Wrap(
      key: const ValueKey('detail-badges'),
      spacing: 8,
      runSpacing: 6,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: AppColors.brandPrimary,
            borderRadius: BorderRadius.circular(AppRadius.pill),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(LucideIcons.footprints, size: 11, color: AppColors.accentOn),
              const SizedBox(width: 5),
              Text(
                'МАРШРУТ',
                style: AppText.label.copyWith(
                  color: AppColors.accentOn,
                  letterSpacing: 0.8,
                ),
              ),
            ],
          ),
        ),
        // Бейдж «ПО ВОДЕ» — сразу за «МАРШРУТОМ» (П3).
        if (isBoat) const BoatBadge(),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: AppPalette.of(context).sandLight,
            borderRadius: BorderRadius.circular(AppRadius.pill),
            border: Border.all(
                color: AppPalette.of(context).sand, width: 1),
          ),
          child: Text(
            formatTrailDistance(trail.distance).toUpperCase(),
            style: AppText.label.copyWith(
              letterSpacing: 0.6,
              color: AppPalette.of(context).onSurface.withValues(alpha: 0.72),
            ),
          ),
        ),
        // «N мест» — в общем потоке бейджей: Wrap не знает Spacer
        // (как у бейджей POI-деталей), на узких — переносится.
        Text(
          '$poiCount ${pluralRu(poiCount, 'место', 'места', 'мест')}',
          style: AppText.caption.copyWith(
            letterSpacing: 0.6,
            color:
                AppPalette.of(context).onSurface.withValues(alpha: 0.72),
          ),
        ),
      ],
    );

    final title = Text(
      trail.name,
      style: AppText.headline.copyWith(
        height: 1.16,
      ),
    );

    final mapPreview = MapPreview(
      onTap: openMap,
      islandId: islandId,
      highlightTrailId: trail.id,
      height: 184,
    );

    final description = trail.description != null
        ? ExpandableText(
            text: trail.description!,
            collapsedLines: 4,
            style: AppText.bodyL.copyWith(
            ),
          )
        : const SizedBox.shrink();

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
                  // Sticky-колонка (B5): галерея-карточка и карта.
                  ImageGallery(
                    imagePaths: galleryImages,
                    videoPath: galleryVideoPath,
                    islandId: islandId,
                    height: galleryHeight,
                    borderRadius: 26,
                    heroPlaceholder: true,
                    placeholderCaption: 'Фото маршрута появятся позже',
                    heroTag: heroTag,
                    // Как на деталях POI (B3.6): первые 12 кадров,
                    // остальное — плитка «Все фото (N)»; карусель
                    // из 229 кадров (Гемилер) листать нереально.
                    maxCarouselFrames: 12,
                  ),
                  const SizedBox(height: 16),
                  MapPreview(
                    onTap: openMap,
                    islandId: islandId,
                    highlightTrailId: trail.id,
                    height: mapHeight,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 20),
            // Align ослабляет tight-констрейнт Expanded (P0-4, 6-й
            // проход): иначе maxWidth 680 зажимался обратно и
            // статья растягивалась на всю колонку.
            Expanded(
              child: Align(
                alignment: Alignment.topLeft,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 680),
                  child: ListView(
                    // Верх правой колонки — ниже плавающих кнопок
                    // «дерево»+«избранное»: иначе бейджи маршрута
                    // попадали под них на 900–1100 px (P0-5).
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
                      // Профиль высот (П5/A5): только у треков с
                      // <ele>, по веткам — разрывы не «мостятся».
                      if (computeElevationStatsSegments(trail.segments)
                          .isNotEmpty) ...[
                        const SizedBox(height: AppSpace.m),
                        ElevationProfile(segments: trail.segments),
                      ],
                      if (trail.description != null) ...[
                        const SizedBox(height: AppSpace.xl),
                        description,
                      ],
                      if (trailPois.isNotEmpty) ...[
                        const SizedBox(height: AppSpace.xl),
                        _pointsSection(ref, favorites),
                      ],
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
        imagePaths: galleryImages,
        videoPath: galleryVideoPath,
        islandId: islandId,
        height: 300 + 150,
        visibleHeight: 300,
        borderRadius: 0,
        bordered: false,
        heroPlaceholder: true,
        placeholderCaption: 'Фото маршрута появятся позже',
        heroTag: heroTag,
        // Как на деталях POI (B3.6): карусель из 229 кадров
        // (Гемилер) листать нереально — 12 + плитка «Все фото».
        maxCarouselFrames: 12,
      ),
    );

    return ListView(

        // Нижний отступ больше высоты плавающих кнопок (52 px +
        // bottom: 12 + нижний жест-бар + запас).
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
                  const SizedBox(height: AppSpace.m),
                  mapPreview,
                  if (trail.description != null) ...[
                    const SizedBox(height: AppSpace.xl),
                    description,
                  ],
                  if (trailPois.isNotEmpty) ...[
                    const SizedBox(height: AppSpace.xl),
                    _pointsSection(ref, favorites),
                  ],
                ],
              ),
            ),
          ),
        ],
      );
        },
    );
  }
}
