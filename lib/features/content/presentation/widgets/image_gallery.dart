import 'dart:ui' show PointerDeviceKind;
import '../../../../core/utils/format.dart';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';
import 'package:smooth_page_indicator/smooth_page_indicator.dart';

import '../../../../app/navigation/navigation_shell.dart';
import '../../../../app/overlay_tracker.dart';
import 'package:video_player/video_player.dart';

import '../../../../app/theme.dart';
import '../../../../core/utils/decode_size.dart';
import '../../../../core/utils/plural.dart';
import '../../../../core/widgets/app_bottom_sheet.dart';
import '../../../../core/widgets/skeleton.dart';
import '../../../../features/content/models/region_catalog.dart';
import '../../../../features/content/providers/content_providers.dart';


/// Открывает полноэкранный зум-просмотр фотографий (B3.6, 8-й
/// проход) на ROOT-навигаторе. Используется и галереей-каруселью,
/// и сеткой «Все фото».
///
/// A3 (10-й проход): просмотр регистрируется в
/// [modalSheetOpenCount] — пилюля мини-плеера живёт НАД
/// Navigator'ом и иначе рисуется поверх чёрного просмотра,
/// перекрывая подпись атрибуции фото.
void showFullscreenGallery(
  BuildContext context, {
  required List<String> imagePaths,
  required String islandId,
  String? videoPath,
  int initialPage = 0,
  String? semanticLabel,
}) {
  modalSheetOpenCount.value++;

  try {
    // Б1: синхронный throw (контекст без Navigator) не должен
    // оставлять счётчик поднятым — пилюля мини-плеера пряталась
    // бы навсегда.
    Navigator.of(context, rootNavigator: true)
        .push(
      PageRouteBuilder<void>(
        opaque: false,
        transitionDuration: AppMotion.normal,
        pageBuilder: (context, animation, secondaryAnimation) {
          return FadeTransition(
            opacity: CurvedAnimation(parent: animation, curve: AppMotion.curve),
            child: _FullscreenGallery(
              imagePaths: imagePaths,
              videoPath: videoPath,
              islandId: islandId,
              initialPage: initialPage,
              semanticLabel: semanticLabel,
            ),
          );
        },
      ),
    )
        .whenComplete(() {
      modalSheetOpenCount.value--;
    });
  } catch (error) {
    modalSheetOpenCount.value--;

    rethrow;
  }
}


/// Сетка «Все фото (N)» (B3.6): ленивый SliverGrid в 3 колонки,
/// тап по кадру — полноэкранный просмотр с этого кадра.
Future<void> showPhotoGridSheet(
  BuildContext context, {
  required List<String> imagePaths,
  required String islandId,
  String? semanticLabel,
}) {
  // Единый каркас шторки (B2, 10-й проход): ручка, шапка,
  // радиус, регистрация в modalSheetOpenCount (A3).
  return showAppBottomSheet(
    context,
    title: 'Все фото (${imagePaths.length})',
    heightFactor: 0.92,
    expandBody: true,
    builder: (sheetContext) {
      return GridView.builder(
        padding: EdgeInsets.fromLTRB(
          16,
          8,
          16,
          NavigationShell.sheetBottomInset(sheetContext),
        ),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
        ),
        itemCount: imagePaths.length,
        itemBuilder: (context, index) {
          final imagePath = imagePaths[index];

          final assetPath =
              '${locationAssetBase(islandId)}/images/$imagePath';

          return GestureDetector(
            onTap: () => showFullscreenGallery(
              context,
              imagePaths: imagePaths,
              islandId: islandId,
              initialPage: index,
              semanticLabel: semanticLabel,
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.tile),
              child: Image.asset(
                assetPath,
                fit: BoxFit.cover,
                // B4 (10-й проход): без прыжков раскладки — скелетон
                // до первого кадра, как в карусели ImageGallery.
                frameBuilder: skeletonFrameBuilder,
                errorBuilder: (_, _, _) => Builder(
                  builder: (context) => Container(
                    color: AppPalette.of(context).sandLight,
                  ),
                ),
              ),
            ),
          );
        },
      );
    },
  );
}


/// Заглушка для отсутствующего/не загрузившегося фото точки.
///
/// Показывается вместо изображения, когда у POI нет фото
/// или ассет не найден (например, реальные исторические
/// снимки ещё не добавлены в офлайн-пакет).
///
/// [hero] — «бумажный» вариант для полноэкранного заголовка
/// деталей: градиент бумага→песок, крупный глиф категории и
/// подпись — не серая «заглушка» (A6).
class ImagePlaceholder extends StatelessWidget {

  const ImagePlaceholder({
    super.key,
    this.height,
    this.borderRadius = 12,
    this.message = 'Фото временно недоступно',
    this.hero = false,
    this.glyph,
    this.glyphColor,
  });


  final double? height;

  final double borderRadius;

  final String message;

  /// Полноэкранный hero-вариант (детали POI/маршрута).
  final bool hero;

  /// Глиф категории (assets/map_icons_flat) — для hero-варианта.
  final String? glyph;

  final Color? glyphColor;


  @override
  Widget build(BuildContext context) {

    final theme = Theme.of(context);

    final palette = AppPalette.of(context);

    final effectiveGlyphColor = glyphColor ?? palette.onSurface;

    return Container(
      height: height,
      width: double.infinity,
      decoration: BoxDecoration(
        // Градиент бумага→песок: тёплый лист, а не серый блок.
        gradient: hero
            ? LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  palette.surface,
                  palette.sandLight,
                  palette.sand.withValues(alpha: 0.55),
                ],
                stops: const [0, 0.55, 1],
              )
            : null,
        color: hero ? null : palette.sandLight,
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(color: palette.sand, width: 1),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (glyph != null)
            // Крупный глиф категории — тот же знак, что и
            // маркер на карте (плоская копия SDF-иконки).
            Container(
              padding: EdgeInsets.all(hero ? 9 : 6),
              decoration: BoxDecoration(
                color: palette.surfaceRaised.withValues(alpha: 0.85),
                shape: BoxShape.circle,
                border: Border.all(
                  color: palette.sand.withValues(alpha: 0.9),
                  width: 1,
                ),
              ),
              child: Image.asset(
                glyph!,
                width: hero ? 30 : 18,
                height: hero ? 30 : 18,
                color: effectiveGlyphColor.withValues(alpha: 0.78),
                colorBlendMode: BlendMode.srcIn,
                errorBuilder: (context, error, stack) => Icon(
                  LucideIcons.camera,
                  size: hero ? 36 : 28,
                  color: AppPalette.of(context).onSurfaceMuted,
                ),
              ),
            )
          else
            Icon(
              LucideIcons.camera,
              size: hero ? 36 : 32,
              color: AppPalette.of(context).onSurfaceMuted,
            ),
          const SizedBox(height: 10),
          Text(
            message,
            textAlign: TextAlign.center,
            style: theme.textTheme.labelSmall?.copyWith(
              fontSize: hero ? 12 : 11,
              letterSpacing: hero ? 0.3 : 0.6,
              color: palette.onSurface.withValues(alpha: hero ? 0.78 : 0.62),
            ),
          ),
        ],
      ),
    );
  }
}


/// Галерея фотографий точки интереса или маршрута.
///
/// Показывает все изображения POI в виде горизонтальной
/// карусели с индикатором страниц. Если фото нет или ассет
/// не загрузился — отображает [ImagePlaceholder].
///
/// [bordered] = false — полноэкранный hero-вариант без рамки
/// (для деталей POI/маршрута, галерея во всю ширину экрана).
class ImageGallery extends StatefulWidget {

  const ImageGallery({
    super.key,
    required this.imagePaths,
    required this.islandId,
    this.videoPath,
    this.height = 220,
    this.borderRadius = 16,
    this.bordered = true,
    this.visibleHeight,
    this.heroPlaceholder = false,
    this.placeholderGlyph,
    this.placeholderCaption,
    this.semanticLabel,
    this.heroTag,
    this.maxCarouselFrames,
  });


  final List<String> imagePaths;

  final String islandId;

  /// Путь к видеофайлу точки (в `images/<id>/`). Видео
  /// показывается последней страницей галереи, после фото.
  final String? videoPath;

  final double height;

  final double borderRadius;

  /// Рисовать ли хайрлайн-рамку вокруг галереи (в hero-режиме
  /// галерея прижата к кромке экрана — рамка не нужна).
  final bool bordered;

  /// Видимая высота галереи, если она выше клипа (параллакс hero
  /// в деталях: галерея 450 px в клипе 300 px, сдвиг −75 px в
  /// покое). Индикаторы (штамп, точки) позиционируются по
  /// видимой зоне — иначе они уезжают за пределы клипа и
  /// пользователь их не видит. `null` — галерея видна целиком.
  final double? visibleHeight;

  /// Пустой hero (нет фото) рисуется градиентным «бумажным»
  /// плейсхолдером с глифом категории (A6).
  final bool heroPlaceholder;

  /// Глиф категории POI для пустого hero-плейсхолдера.
  final String? placeholderGlyph;

  /// Подпись пустого hero-плейсхолдера (например, «Бухта · фото
  /// появятся позже»).
  final String? placeholderCaption;

  /// Название точки для семантики кадров («Фото 2 из 5: …»).
  final String? semanticLabel;

  /// Тег Hero-перехода для первого кадра: полёт фото из
  /// миниатюры списка в полноэкранный hero деталей (B7).
  final String? heroTag;

  /// Лимит кадров карусели (B3.6, 8-й проход): галереи длинных
  /// точек показывают первые N кадров, последний «слайд» —
  /// «Все фото (M)» с сеткой. `null` — без лимита (прежнее
  /// поведение).
  final int? maxCarouselFrames;


  @override
  State<ImageGallery> createState() => _ImageGalleryState();
}


class _ImageGalleryState extends State<ImageGallery> {

  int _current = 0;

  bool _hovered = false;

  final FocusNode _focusNode = FocusNode(
    debugLabel: 'ImageGallery',
  );

  final PageController _controller =
      PageController(keepPage: true);


  /// Кадры карусели: первые maxCarouselFrames фото (лимит B3.6).
  List<String> get carouselFrames {
    final max = widget.maxCarouselFrames;

    if (max == null || widget.imagePaths.length <= max) {
      return widget.imagePaths;
    }

    return widget.imagePaths.take(max).toList();
  }

  /// Есть ли плитка «Все фото (N)» в конце карусели.
  bool get _hasMoreTile =>
      widget.maxCarouselFrames != null &&
      widget.imagePaths.length > widget.maxCarouselFrames!;

  /// Число РЕАЛЬНЫХ кадров (D5, замечание Sonnet): фото + видео —
  /// как в полноэкранном просмотре. Плитка «Все фото» кадром не
  /// считается: раньше штамп показывал «13 / 13» при 12 фото и
  /// расходился с «N / M» фуллскрина.
  int get _realFrameCount =>
      widget.imagePaths.length + (widget.videoPath != null ? 1 : 0);

  /// Штамп для текущего слайда: ТОЛЬКО РЕАЛЬНЫЕ кадры карусели
  /// (`N / M`, M — фото+видео, как в фуллскрине). Виден ВСЕГДА —
  /// пользователь должен видеть, сколько у точки фото: одна
  /// фото или листать. Видео-слайд и плитка «Все фото» штампа
  /// не имеют (при maxCarouselFrames=12 и 20 фото плитка на
  /// индексе 12 получала «13 / 20»).
  String? get _stampLabel {
    if (_current >= carouselFrames.length || carouselFrames.isEmpty) {
      return null;
    }

    return '${_current + 1} / $_realFrameCount';
  }

  /// Общее число слайдов: кадры + видео (последней страницей) +
  /// плитка «Все фото».
  int get _pageCount =>
      carouselFrames.length +
      (widget.videoPath != null ? 1 : 0) +
      (_hasMoreTile ? 1 : 0);


  /// Touch-режим: нативные мобильные платформы и мобильный web
  /// (`defaultTargetPlatform` на web — ОС браузера). Свайпа
  /// достаточно, стрелки не показываем (B8).
  bool get _touchMode => switch (defaultTargetPlatform) {
        TargetPlatform.android ||
        TargetPlatform.iOS ||
        TargetPlatform.fuchsia =>
          true,
        _ => false,
      };


  @override
  void dispose() {
    _controller.dispose();

    _focusNode.dispose();

    super.dispose();
  }


  void _goToPage(int index) {

    if (index < 0 ||
        index >= _pageCount) {
      return;
    }

    _controller.animateToPage(
      index,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );

    setState(() {
      _current = index;
    });
  }

  /// Полноэкранный просмотр с зумом, счётчиком «N / M» и
  /// закрытием свайпом вниз (P1-2). Route на ROOT-навигаторе —
  /// поверх шелла и деталей; hero-полёт кадра работает на
  /// страницах деталей (тот же навигатор).
  ///
  /// A4 (11-й проход): из карусели открываются ВСЕ фото точки
  /// (не только кадры карусели до лимита) — счётчик «N / M»
  /// совпадает с сеткой «Все фото». Индекс кадра карусели —
  /// это и индекс в полном списке: кадры карусели — префикс.
  void _openFullscreen(int initialPage) {
    showFullscreenGallery(
      context,
      imagePaths: widget.imagePaths,
      videoPath: widget.videoPath,
      islandId: widget.islandId,
      initialPage: initialPage,
      semanticLabel: widget.semanticLabel,
    );
  }


  @override
  Widget build(BuildContext context) {

    if (_pageCount == 0) {

      return ImagePlaceholder(
        height: widget.height,
        borderRadius: widget.borderRadius,
        hero: widget.heroPlaceholder,
        glyph: widget.heroPlaceholder ? widget.placeholderGlyph : null,
        message: widget.heroPlaceholder
            ? (widget.placeholderCaption ?? 'Фото пока не добавлены')
            : 'Фото временно недоступно',
      );
    }

    final indicatorShift =
        widget.visibleHeight == null || widget.visibleHeight! >= widget.height
            ? 0.0
            : (widget.height - widget.visibleHeight!) / 2;

    // Стрелки — только на десктопе: показываются при наведении
    // курсора или клавиатурном фокусе (B8).
    final showArrows = _pageCount > 1 && !_touchMode;

    final arrowsVisible = showArrows && (_hovered || _focusNode.hasFocus);

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Focus(
        focusNode: _focusNode,
        onFocusChange: (focused) {
          if (focused) setState(() {});
        },
        child: CallbackShortcuts(
          bindings: <ShortcutActivator, VoidCallback>{
            const SingleActivator(LogicalKeyboardKey.arrowLeft):
                () => _goToPage(_current - 1),
            const SingleActivator(LogicalKeyboardKey.arrowRight):
                () => _goToPage(_current + 1),
          },
          child: Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(widget.borderRadius),
        border: widget.bordered
            ? Border.all(color: AppPalette.of(context).sand, width: 1)
            : null,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(
              widget.bordered ? widget.borderRadius - 1 : 0,
            ),
            child: SizedBox(
              height: widget.height,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  PageView.builder(
                    controller: _controller,
                    itemCount: _pageCount,
                    scrollBehavior: const MaterialScrollBehavior().copyWith(
                      dragDevices: {
                        PointerDeviceKind.touch,
                        PointerDeviceKind.mouse,
                        PointerDeviceKind.stylus,
                        PointerDeviceKind.trackpad,
                      },
                    ),
                    onPageChanged: (index) {

                      setState(() {
                        _current = index;
                      });
                    },
                    itemBuilder: (context, index) {
                      // Пункт 9 (замечания Sonnet): единый выбор типа
                      // слайда — фото / видео / плитка «Все фото» —
                      // без двух повторяющихся проверок видео-слайда.
                      final tileIndex = carouselFrames.length +
                          (widget.videoPath != null ? 1 : 0);

                      if (index >= tileIndex) {
                        return GestureDetector(
                          onTap: () => showPhotoGridSheet(
                            context,
                            imagePaths: widget.imagePaths,
                            islandId: widget.islandId,
                            semanticLabel: widget.semanticLabel,
                          ),
                          child: Semantics(
                            button: true,
                            label:
                                'Все фото (${widget.imagePaths.length} '
                                '${pluralRu(widget.imagePaths.length, 'кадр', 'кадра', 'кадров')})',
                            child: _AllPhotosTile(
                              total: widget.imagePaths.length,
                            ),
                          ),
                        );
                      }

                      if (index >= carouselFrames.length) {
                        return _VideoSlide(
                          assetPath: '${locationAssetBase(widget.islandId)}'
                              '/images/${widget.videoPath}',
                          borderRadius: widget.borderRadius,
                          active: index == _current,
                        );
                      }

                      final label =
                          'Фото ${index + 1} из ${_realFrameCount > 0 ? _realFrameCount : 1}'
                          '${widget.semanticLabel != null
                              ? ': ${widget.semanticLabel}' : ''}';

                      final imagePath =
                          '${locationAssetBase(widget.islandId)}'
                          '/images/${carouselFrames[index]}';

                      final photo = Builder(
                        builder: (context) => GestureDetector(
                          onTap: () => _openFullscreen(index),
                          child: Image.asset(
                          imagePath,
                          width: double.infinity,
                          fit: BoxFit.cover,
                          semanticLabel: label,
                          // Слайд галереи не шире экрана: не декодируем
                          // полноразмерные фото (~1200 px) без нужды.
                          cacheWidth: decodeWidthPx(
                            context,
                            MediaQuery.sizeOf(context).width,
                            oversample: 1,
                          ),
                          // Плавное появление кадра + скелетон вместо
                          // пустоты, пока кадр декодируется.
                          frameBuilder: skeletonFrameBuilder,
                          errorBuilder: (context, error, stack) {

                            return ImagePlaceholder(
                              height: widget.height,
                              borderRadius: widget.borderRadius,
                            );
                          },
                        ),
                        ),
                      );

                      // Первый кадр участвует в Hero-полёте из
                      // миниатюры списка (B7). Shuttle-строитель
                      // рисует фото cover-ом: полёт не зависит от
                      // клипов галереи (OverflowBox параллакса).
                      if (index == 0 && widget.heroTag != null) {
                        return Hero(
                          tag: widget.heroTag!,
                          flightShuttleBuilder:
                              (flightContext, animation, direction,
                                  fromHeroContext, toHeroContext) {
                            return Image.asset(
                              imagePath,
                              fit: BoxFit.cover,
                              cacheWidth: decodeWidthPx(
                                flightContext,
                                MediaQuery.sizeOf(flightContext).width,
                                oversample: 1,
                              ),
                            );
                          },
                          child: photo,
                        );
                      }

                      return photo;
                    },
                  ),

                  // Штамп «N / M» — всегда виден: пользователь
                  // должен знать, сколько фото у точки (одна
                  // фото или листать; у одиночного — «1 / 1»).
                  // Счёт — по РЕАЛЬНЫМ кадрам (D5), плитка «Все
                  // фото» штампа не имеет.
                  if (_stampLabel != null)
                    Positioned(
                      left: 12,
                      top: 12 + indicatorShift,
                      // Штамп — визуальный дубль semanticLabel кадра
                      // («Фото 1 из 20: …»): из семантики убран,
                      // чтобы TalkBack не читал «1 слэш 20» (D3).
                      child: ExcludeSemantics(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3.5,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.scrimInk.withValues(alpha: 0.66),
                          borderRadius: BorderRadius.circular(AppRadius.pill),
                        ),
                        child: Text(
                          _stampLabel!,
                          style: AppText.label.copyWith(
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.6,
                            color: AppColors.onScrim,
                          ),
                        ),
                      ),
                      ),
                    ),

                  if (showArrows) ...[

                    _NavArrow(
                      tooltip: 'Предыдущее фото',
                      icon: LucideIcons.chevronLeft,
                      visible: arrowsVisible,
                      onPressed:
                          _current > 0 ? () => _goToPage(_current - 1) : null,
                    ),

                    _NavArrow(
                      tooltip: 'Следующее фото',
                      icon: LucideIcons.chevronRight,
                      visible: arrowsVisible,
                      onPressed: _current < _pageCount - 1
                          ? () => _goToPage(_current + 1)
                          : null,
                    ),
                  ],

                  // Точки-индикатор: прогресс листания для 2–8
                  // кадров (дальше ряд не читается — позицию
                  // показывает всегда видимый штамп «N / M»). У
                  // галереи с видео последняя точка — значок
                  // «видео» (P1-2).
                  if (_pageCount > 1 && _pageCount <= 8)

                    Positioned(
                      bottom: 10 + indicatorShift,
                      left: 0,
                      right: 0,
                      child: Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.scrimInk.withValues(alpha: 0.78),
                            borderRadius: BorderRadius.circular(AppRadius.pill),
                          ),
                          child: widget.videoPath != null
                              ? Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    // Точек — сколько кадров в
                                    // КАРУСЕЛИ (A3, 11-й проход):
                                    // раньше счёт шёл по всем фото
                                    // точки, и при лимите
                                    // maxCarouselFrames значок
                                    // «видео» подсвечивался не на
                                    // своей странице.
                                    for (var i = 0;
                                        i < carouselFrames.length;
                                        i++)
                                      _GalleryDot(
                                        key: ValueKey('gallery-dot-$i'),
                                        active: _current == i,
                                      ),
                                    const SizedBox(width: 4),
                                    _GalleryVideoDot(
                                      key: const ValueKey('gallery-video-dot'),
                                      active:
                                          _current == carouselFrames.length,
                                    ),
                                  ],
                                )
                              : SmoothPageIndicator(
                                  controller: _controller,
                                  count: _pageCount,
                                  effect: WormEffect(
                                    activeDotColor: AppColors.onScrim,
                                    dotColor:
                                        AppColors.onScrim.withValues(alpha: 0.46),
                                    dotHeight: 5,
                                    dotWidth: 5,
                                    radius: 3,
                                    spacing: 4,
                                  ),
                                ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
          ),
        ),
      ),
    );
  }
}


/// Плитка «Все фото (N)» — последний слайд карусели длинной
/// галереи (B3.6, 8-й проход): «бумажный» фон, глиф сетки и
/// число кадров; тап открывает сетку со всеми кадрами.
class _AllPhotosTile extends StatelessWidget {
  const _AllPhotosTile({required this.total});

  final int total;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            AppPalette.of(context).sandLight,
            AppPalette.of(context).sand.withValues(alpha: 0.55),
          ],
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: AppColors.surfaceRaised.withValues(alpha: 0.85),
              shape: BoxShape.circle,
              border: Border.all(
                color: AppPalette.of(context).sand.withValues(alpha: 0.9),
              ),
            ),
            child: const Icon(
              LucideIcons.grid3x3,
              size: 24,
              color: AppColors.depth,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Все фото',
            style: AppText.chip.copyWith(
                  color: AppPalette.of(context).onSurface,
                ),
          ),
          const SizedBox(height: 2),
          Text(
            // Склонение (A2, 11-й проход): «21 кадр» вместо
            // «21 кадров».
            '$total ${pluralRu(total, 'кадр', 'кадра', 'кадров')}',
            style: AppText.label.copyWith(
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.4,
                  color: AppPalette.of(context).onSurfaceMuted,
                ),
          ),
        ],
      ),
    );
  }
}

/// Стрелка навигации по галерее: белая иконка на
/// тёмном полупрозрачном квадратике. На десктопе появляется
/// при наведении/фокусе (плавная прозрачность, вне hover
/// тапы игнорируются), на touch платформах не показывается
/// вовсе — достаточно свайпа (B8).
class _NavArrow extends StatelessWidget {

  const _NavArrow({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.visible = true,
  });


  final String tooltip;

  final IconData icon;

  final VoidCallback? onPressed;

  /// Показана ли стрелка (hover/фокус на десктопе).
  final bool visible;


  @override
  Widget build(BuildContext context) {

    return Positioned(
      top: 0,
      bottom: 0,
      left: icon == LucideIcons.chevronLeft ? 8 : null,
      right: icon == LucideIcons.chevronRight ? 8 : null,
      child: Center(
        child: AnimatedOpacity(
          duration: AppMotion.fast,
          curve: AppMotion.curve,
          opacity: visible ? 1 : 0,
          child: IgnorePointer(
            ignoring: !visible,
            child: Semantics(
              button: true,
              label: tooltip,
              child: GestureDetector(
                onTap: onPressed,
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: AppColors.scrimInk.withValues(alpha: 0.42),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    icon,
                    color: onPressed == null
                        ? AppColors.onScrim.withValues(alpha: 0.4)
                        : AppColors.onScrim,
                    size: 22,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}


/// Слайд галереи с видео: тёмный фон, кнопка воспроизведения
/// и прогресс-бар. Видео запускается автоматически, когда слайд
/// становится активной страницей галереи ([active] == true),
/// и ставится на паузу, когда уходит. Тап — play/pause.
class _VideoSlide extends StatefulWidget {

  const _VideoSlide({
    required this.assetPath,
    required this.borderRadius,
    required this.active,
  });


  final String assetPath;

  final double borderRadius;

  /// Активная ли это страница галереи (текущий слайд).
  final bool active;


  @override
  State<_VideoSlide> createState() => _VideoSlideState();
}


class _VideoSlideState extends State<_VideoSlide> {

  VideoPlayerController? _controller;

  bool _initialized = false;

  bool _failed = false;


  @override
  void initState() {

    super.initState();

    _init();
  }


  Future<void> _init() async {

    final controller = VideoPlayerController.asset(widget.assetPath);

    try {

      await controller.initialize();

      if (!mounted) {
        await controller.dispose();
        return;
      }

      setState(() {
        _controller = controller;
        _initialized = true;
      });

      // Видео запускается автоматически, если слайд уже активен.
      if (widget.active) {
        await controller.play();
      }

    } catch (_) {

      if (mounted) {
        setState(() {
          _failed = true;
        });
      }
    }
  }


  @override
  void didUpdateWidget(_VideoSlide oldWidget) {

    super.didUpdateWidget(oldWidget);

    final controller = _controller;

    if (controller == null || !_initialized) {
      return;
    }

    if (widget.active && !oldWidget.active) {

      controller.play();

    } else if (!widget.active && oldWidget.active) {

      controller.pause();
    }
  }


  @override
  void dispose() {

    _controller?.dispose();

    super.dispose();
  }


  @override
  Widget build(BuildContext context) {

    if (_failed) {

      return const ImagePlaceholder(
        message: 'Видео временно недоступно',
      );
    }

    final controller = _controller;

    if (!_initialized || controller == null) {
      // Загрузка — в языке «бумажных» скелетонов (B3, 11-й
      // проход): фон sandLight + волна + глиф play, а не
      // чёрный экран со стандартным спиннером.
      return Stack(
        fit: StackFit.expand,
        children: [
          const SkeletonBox(radius: 0),
          Center(
            child: Icon(
              LucideIcons.play,
              size: 36,
              color: AppPalette.of(context).onSurfaceMuted,
            ),
          ),
        ],
      );
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {

        if (controller.value.isPlaying) {
          controller.pause();
        } else {
          controller.play();
        }
      },
      child: Stack(
        fit: StackFit.expand,
        children: [
          Center(
            child: AspectRatio(
              aspectRatio: controller.value.aspectRatio,
              child: VideoPlayer(controller),
            ),
          ),

          if (!controller.value.isPlaying)

            Center(
              child: Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  // Скрим — роль, не голый чёрный (B1, 11-й проход).
                  color: AppColors.scrimDark.withValues(alpha: 0.5),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  LucideIcons.play,
                  color: AppColors.onScrim,
                  size: 36,
                ),
              ),
            ),

          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _VideoProgress(controller),
          ),
        ],
      ),
    );
  }
}


/// Прогресс-бар видео с подписью времени.
class _VideoProgress extends StatelessWidget {

  const _VideoProgress(this.controller);


  final VideoPlayerController controller;


  @override
  Widget build(BuildContext context) {

    return ValueListenableBuilder(
      valueListenable: controller,
      builder: (context, value, _) {

        final duration = value.duration;

        if (duration == Duration.zero) {
          return const SizedBox.shrink();
        }

        final position = value.position;

        return Container(
          color: AppColors.scrimDark.withValues(alpha: 0.55),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [

              LinearProgressIndicator(
                value: (position.inMilliseconds /
                        duration.inMilliseconds)
                    .clamp(0.0, 1.0),
                backgroundColor: AppColors.onScrim.withValues(alpha: 0.25),
                color: AppColors.onScrim,
                minHeight: 3,
              ),

              const SizedBox(height: 4),

              Text(
                '${formatDuration(position)} / ${formatDuration(duration)}',
                style: AppText.label.copyWith(
                  color: AppColors.onScrim,
                ),
              ),
            ],
          ),
        );
      },
    );
  }


}


/// Точка-индикатор галереи с видео: единый ряд обычных точек,
/// последняя — значок «видео» (P1-2).
class _GalleryDot extends StatelessWidget {
  const _GalleryDot({super.key, required this.active});

  final bool active;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: AppMotion.curve,
      width: active ? 16 : 5,
      height: 5,
      margin: const EdgeInsets.symmetric(horizontal: 2),
      decoration: BoxDecoration(
        color: active ? AppColors.onScrim : AppColors.onScrim.withValues(alpha: 0.46),
        borderRadius: BorderRadius.circular(AppRadius.mini),
      ),
    );
  }
}

class _GalleryVideoDot extends StatelessWidget {
  const _GalleryVideoDot({super.key, required this.active});

  final bool active;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: AppMotion.curve,
      width: 16,
      height: 16,
      decoration: BoxDecoration(
        color: active ? AppColors.onScrim : AppColors.onScrim.withValues(alpha: 0.46),
        shape: BoxShape.circle,
      ),
      child: Icon(
        LucideIcons.play,
        size: 9,
        color: active
            ? AppColors.scrimInk
            : AppColors.onScrim,
      ),
    );
  }
}


/// Полноэкранный просмотр фотографий (P1-2): зум щипком
/// (InteractiveViewer), счётчик «N / M», закрытие кнопкой и
/// СВАЙПОМ ВНИЗ (Listener — вне арены жестов: PageView и
/// InteractiveViewer не мешают), hero-полёт кадра на
/// страницах деталей.
class _FullscreenGallery extends ConsumerStatefulWidget {
  const _FullscreenGallery({
    required this.imagePaths,
    required this.islandId,
    this.videoPath,
    required this.initialPage,
    this.semanticLabel,
  });

  final List<String> imagePaths;

  final String islandId;

  final String? videoPath;

  final int initialPage;

  final String? semanticLabel;

  @override
  ConsumerState<_FullscreenGallery> createState() => _FullscreenGalleryState();
}

class _FullscreenGalleryState extends ConsumerState<_FullscreenGallery> {
  late final PageController _controller;

  int _current = 0;

  /// Увеличена ли ТЕКУЩАЯ страница. Каждая страница держит свой
  /// TransformationController (P0-9, 6-й проход): раньше один
  /// контроллер на все страницы — при зуме соседние кадры во
  /// время свайпа получали тот же масштаб.
  bool _currentPageZoomed = false;

  /// Накопленный свайп вниз (закрытие) и вбок (для отсечки
  /// горизонтального свайпа страниц).
  double _dragDy = 0;

  double _dragDx = 0;

  /// Активные указатели на экране.
  final Set<int> _activePointers = {};

  /// Основной (первый) указатель: закрытие отслеживает только
  /// его — вторая точка касания означает щипок, а не свайп
  /// (P0-4, 7-й проход).
  int? _primaryPointer;

  /// Было второе касание: до подъёма ПОСЛЕДНЕГО пальца закрытие
  /// запрещено — раньше суммарная dy двух пальцев щипка
  /// закрывала просмотр на 1× без всякого зума.
  bool _multiTouch = false;

  int get _pageCount =>
      widget.imagePaths.length + (widget.videoPath != null ? 1 : 0);

  /// Touch-режим (как в основной галерее): стрелки и hover
  /// не нужны, свайп достаточен (A7, 8-й проход).
  bool get _touchMode => switch (defaultTargetPlatform) {
        TargetPlatform.android ||
        TargetPlatform.iOS ||
        TargetPlatform.fuchsia =>
          true,
        _ => false,
      };

  /// Показывать стрелки (десктоп: по hover).
  bool _hovered = false;

  /// Переключение страницы (клавиши ←/→ и стрелки на десктопе,
  /// A7). Увеличенный кадр не листается — как и свайпом (P0-9).
  void _goToPage(int index) {
    if (index < 0 || index >= _pageCount || _currentPageZoomed) {
      return;
    }

    _controller.animateToPage(
      index,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  @override
  void initState() {
    super.initState();

    _current = widget.initialPage;

    _controller = PageController(initialPage: widget.initialPage);
  }

  @override
  void dispose() {
    _controller.dispose();

    super.dispose();
  }

  /// Отчёт зума активной страницы: может прийти прямо в момент
  /// перестроения родителя (didUpdateWidget страницы при смене
  /// активной) — setState в build-фазе нельзя, планируем после
  /// кадра.
  void _onActiveZoomChanged(bool zoomed) {
    if (zoomed == _currentPageZoomed) {
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && zoomed != _currentPageZoomed) {
        setState(() {
          _currentPageZoomed = zoomed;
        });
      }
    });
  }

  void _onPointerDown(PointerDownEvent event) {
    _activePointers.add(event.pointer);

    if (_primaryPointer == null) {
      _primaryPointer = event.pointer;

      _dragDy = 0;

      _dragDx = 0;

      return;
    }

    // Вторая точка касания: это щипок, а не свайп — накопление
    // сбрасываем и запрещаем закрытие до последнего up.
    _multiTouch = true;

    final hadDrag = _dragDy != 0;

    _dragDy = 0;

    _dragDx = 0;

    if (hadDrag) {
      setState(() {});
    }
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (_currentPageZoomed ||
        _multiTouch ||
        event.pointer != _primaryPointer) {
      return;
    }

    _dragDy += event.delta.dy;

    _dragDx += event.delta.dx;

    if (_dragDy > 0 && _dragDy > _dragDx.abs()) {
      setState(() {});
    }
  }

  void _onPointerEnd(PointerEvent event) {
    _activePointers.remove(event.pointer);

    // Пока хоть один палец на экране — закрытие не оцениваем
    // (флаг мультитача живёт до последнего up).
    if (_activePointers.isNotEmpty) {
      return;
    }

    final wasMultiTouch = _multiTouch;

    _primaryPointer = null;

    _multiTouch = false;

    final drag = _dragDy;

    final dragX = _dragDx.abs();

    _dragDy = 0;

    _dragDx = 0;

    // Закрытие — только ОДНОпальцевый свайп вниз, явно
    // вертикальный: dy > 110 и dy > |dx| * 1.5. Диагональный
    // свайп (листание/пан) и щипок просмотр не закрывают
    // (P0-4, 7-й проход).
    if (!_currentPageZoomed &&
        !wasMultiTouch &&
        drag > 110 &&
        drag > dragX * 1.5) {
      Navigator.of(context).pop();

      return;
    }

    if (drag != 0) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.paddingOf(context).top;

    final dragOffset =
        _currentPageZoomed ? 0.0 : (_dragDy > 0 ? _dragDy : 0.0);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
      ),
      child: Scaffold(
        backgroundColor: AppColors.scrimDark,
        // Клавиатура на десктопе (A7, 8-й проход): ←/→ листают
        // кадры, Esc закрывает просмотр. Autofocus — роут пушится
        // поверх, фокус сразу на просмотре.
        body: CallbackShortcuts(
          bindings: <ShortcutActivator, VoidCallback>{
            const SingleActivator(LogicalKeyboardKey.arrowLeft):
                () => _goToPage(_current - 1),
            const SingleActivator(LogicalKeyboardKey.arrowRight):
                () => _goToPage(_current + 1),
            const SingleActivator(LogicalKeyboardKey.escape):
                () => Navigator.of(context).pop(),
          },
          child: Focus(
            autofocus: true,
            child: MouseRegion(
              onEnter: (_) => setState(() => _hovered = true),
              onExit: (_) => setState(() => _hovered = false),
              child: Listener(
          onPointerDown: _onPointerDown,
          onPointerMove: _onPointerMove,
          onPointerUp: _onPointerEnd,
          onPointerCancel: _onPointerEnd,
          child: Stack(
            children: [
              Positioned.fill(
                child: Opacity(
                  opacity: (1 - dragOffset / 320).clamp(0.5, 1.0),
                  child: Transform.translate(
                    offset: Offset(0, dragOffset * 0.4),
                    child: PageView.builder(
                      controller: _controller,
                      // Увеличенный кадр панорамируется, а не
                      // листается: пан фото не конфликтует с
                      // перелистыванием (P0-9).
                      physics: _currentPageZoomed
                          ? const NeverScrollableScrollPhysics()
                          : null,
                      itemCount: _pageCount,
                      onPageChanged: (index) {
                        setState(() {
                          _current = index;

                          // Страница сменилась — текущим стал другой
                          // кадр; его реальный зум активная страница
                          // доложит сама (didUpdateWidget).
                          _currentPageZoomed = false;
                        });
                      },
                      itemBuilder: (context, index) {
                        if (widget.videoPath != null &&
                            index >= widget.imagePaths.length) {
                          return _VideoSlide(
                            assetPath:
                                '${locationAssetBase(widget.islandId)}'
                                '/images/${widget.videoPath}',
                            borderRadius: 0,
                            active: index == _current,
                          );
                        }

                        final label =
                            'Фото ${index + 1} из $_pageCount'
                            '${widget.semanticLabel != null
                                ? ': ${widget.semanticLabel}' : ''}';

                        return _ZoomablePhoto(
                          assetPath:
                              '${locationAssetBase(widget.islandId)}'
                              '/images/${widget.imagePaths[index]}',
                          semanticLabel: label,
                          active: index == _current,
                          onActiveZoomChanged: _onActiveZoomChanged,
                        );
                      },
                    ),
                  ),
                ),
              ),

              // Счётчик «N / M» — всегда виден (P1-2).
              Positioned(
                top: topInset + 10,
                left: 0,
                right: 0,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.scrimDark.withValues(alpha: 0.45),
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                    ),
                    child: Text(
                      '${_current + 1} / $_pageCount',
                      style: AppText.caption.copyWith(
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.6,
                        color: AppColors.onScrim,
                      ),
                    ),
                  ),
                ),
              ),

              // Подпись атрибуции фото (A9, 8-й проход):
              // лицензии CC BY / CC BY-SA требуют автора и
              // лицензию РЯДОМ с изображением. Нижняя полоса,
              // мелкий текст, полупрозрачная подложка; нет данных —
              // полосы нет (источник не найден — не выдумываем).
              Builder(
                builder: (context) {
                  final imagePath = _current < widget.imagePaths.length
                      ? widget.imagePaths[_current]
                      : null;

                  final credit = imagePath == null
                      ? null
                      : ref
                          .watch(photoCreditsFamily(widget.islandId))
                          .value?[imagePath];

                  final caption = credit?.caption;

                  if (caption == null) {
                    // Пустой кредит — тоже Positioned: голый
                    // SizedBox.shrink() как НЕпозиционированный
                    // ребёнок сжимал Stack до нуля и обнулял
                    // PageView (viewport без visible-геометрии —
                    // фаиндеры и клики не видели фото).
                    return const Positioned(
                      left: 0,
                      top: 0,
                      child: SizedBox.shrink(),
                    );
                  }

                  final bottomInset =
                      MediaQuery.paddingOf(context).bottom;

                  return Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: Container(
                      color: AppColors.scrimDark.withValues(alpha: 0.45),
                      padding: EdgeInsets.fromLTRB(
                        16,
                        7,
                        16,
                        7 + bottomInset,
                      ),
                      child: Text(
                        caption,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: AppText.label.copyWith(
                          height: 1.35,
                          letterSpacing: 0.3,
                          color: AppColors.onScrim.withValues(alpha: 0.7),
                        ),
                      ),
                    ),
                  );
                },
              ),

              // Стрелки на десктопе — по hover, как в обычной
              // галерее (A7): появляются при наведении, на touch
              // платформах скрыты — достаточно свайпа.
              if (!_touchMode && _pageCount > 1) ...[
                _NavArrow(
                  tooltip: 'Предыдущее фото',
                  icon: LucideIcons.chevronLeft,
                  visible: _hovered,
                  onPressed:
                      _current > 0 ? () => _goToPage(_current - 1) : null,
                ),
                _NavArrow(
                  tooltip: 'Следующее фото',
                  icon: LucideIcons.chevronRight,
                  visible: _hovered,
                  onPressed: _current < _pageCount - 1
                      ? () => _goToPage(_current + 1)
                      : null,
                ),
              ],

              Positioned(
                top: topInset + 8,
                right: 12,
                // PointerInterceptor: на web платформенный канвас
                // карты под route всё ещё ловит тапы — кнопка
                // обязана перехватывать их себе.
                child: PointerInterceptor(
                  child: IconButton(
                    tooltip: 'Закрыть просмотр',
                    onPressed: () => Navigator.of(context).pop(),
                    style: IconButton.styleFrom(
                      backgroundColor:
                          AppColors.scrimDark.withValues(alpha: 0.45),
                      foregroundColor: AppColors.onScrim,
                      minimumSize: const Size(44, 44),
                    ),
                    icon: const Icon(LucideIcons.x, size: 22),
                  ),
                ),
              ),
            ],
          ),
        ),
        ),
          ),
        ),
      ),
    );
  }
}


/// Кадр полноэкранного просмотрщика: СВОЙ TransformationController
/// (P0-9, 6-й проход — раньше один контроллер делили все страницы
/// PageView, и при зуме соседние кадры во время свайпа получали
/// тот же масштаб) и двойной тап — переключение 1× ↔ 2.5×.
class _ZoomablePhoto extends StatefulWidget {
  const _ZoomablePhoto({
    required this.assetPath,
    required this.semanticLabel,
    required this.active,
    required this.onActiveZoomChanged,
  });

  final String assetPath;

  final String semanticLabel;

  /// Активная (текущая) страница галереи.
  final bool active;

  /// Активная страница докладывает свой зум родителю: PageView
  /// переключает физику листания, свайп-вниз не закрывает.
  final ValueChanged<bool> onActiveZoomChanged;

  @override
  State<_ZoomablePhoto> createState() => _ZoomablePhotoState();
}

class _ZoomablePhotoState extends State<_ZoomablePhoto> {
  final TransformationController _zoom = TransformationController();

  @override
  void initState() {
    super.initState();

    _zoom.addListener(_reportZoom);
  }

  @override
  void didUpdateWidget(covariant _ZoomablePhoto oldWidget) {
    super.didUpdateWidget(oldWidget);

    // Страница стала текущей — родителю нужен её фактический
    // зум (кадр мог остаться увеличенным с прошлого просмотра).
    if (widget.active != oldWidget.active && widget.active) {
      _reportZoom();
    }
  }

  @override
  void dispose() {
    _zoom.dispose();

    super.dispose();
  }

  bool get _zoomed => _zoom.value.getMaxScaleOnAxis() > 1.01;

  void _reportZoom() {
    if (widget.active) {
      widget.onActiveZoomChanged(_zoomed);
    }
  }

  /// Двойной тап — переключение зума 1× ↔ 2.5× (P0-9).
  void _onDoubleTap() {
    _zoom.value = _zoomed
        ? Matrix4.identity()
        : Matrix4.diagonal3Values(2.5, 2.5, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    // Без Hero: раньше кадр обёртывался в Hero с тегом
    // gallery-zoom-<island>-<index>, но в галерее-источнике Hero
    // есть только у первого кадра (тег poi-image-…) — пары не
    // существовало никогда, полёта не было. Открытие/закрытие
    // анимирует FadeTransition роута (P1-4, 7-й проход).
    return GestureDetector(
      onDoubleTap: _onDoubleTap,
      child: InteractiveViewer(
        transformationController: _zoom,
        maxScale: 4,
        child: Center(
          child: Image.asset(
            widget.assetPath,
            fit: BoxFit.contain,
            semanticLabel: widget.semanticLabel,
            // Ассета может не быть (пакет в разработке) —
            // чёрный фон с короткой подписью, без необработанных
            // ошибок декодера.
            errorBuilder: (context, error, stack) {
              return Center(
                child: Text(
                  'Фотография недоступна',
                  style: AppText.chip.copyWith(
                    fontWeight: FontWeight.w400,
                    color: AppColors.onScrim.withValues(alpha: 0.7),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
