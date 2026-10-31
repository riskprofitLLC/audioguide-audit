import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/theme.dart';
import '../../core/utils/decode_size.dart';
import 'skeleton.dart';
import '../../core/utils/plural.dart';
import '../../features/favorites/presentation/widgets/favorite_star.dart';
import '../../features/trails/utils/format_distance.dart';
import '../../features/trails/presentation/widgets/boat_badge.dart';


/// Универсальная карточка: плоский лист атласа — только
/// hairline-рамка, без тени (редизайн «Атлас»).
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.padding,
    this.margin,
    this.elevation,
    this.borderRadius = AppRadius.card,
    this.borderColor,
    this.borderWidth = 1,
    this.onTap,
    this.clipBehavior = Clip.antiAlias,
    this.color,
    this.shadowColor,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final double? elevation;
  final double borderRadius;
  final Color? borderColor;
  final double borderWidth;
  final VoidCallback? onTap;
  final Clip clipBehavior;
  final Color? color;
  final Color? shadowColor;

  @override
  Widget build(BuildContext context) {
    // Фон карточки — ролевой (B5): surfaceRaised палитры.
    // Светлая тема — тот же белый лист, тёмная — тёмный.
    final palette = AppPalette.of(context);

    final card = DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(borderRadius),
        // Тень убрана: карточки атласа плоские (редизайн «Атлас»).
      ),
      child: Material(
        color: color ?? palette.surfaceRaised,
        elevation: elevation ?? 0,
        surfaceTintColor: Colors.transparent,
        borderRadius: BorderRadius.circular(borderRadius),
        clipBehavior: clipBehavior,
        child: InkWell(
          // Ripple ВНУТРИ Material, поверх фона: раньше InkWell
          // лежал снаружи — непрозрачный фон карточки перекрывал
          // волну, и отклик на тап был невидим (A3).
          onTap: onTap,
          borderRadius: BorderRadius.circular(borderRadius),
          splashColor: AppColors.brandPrimary.withValues(alpha: 0.08),
          highlightColor: AppColors.brandPrimary.withValues(alpha: 0.04),
          hoverColor: onTap != null
              ? AppColors.brandPrimary.withValues(alpha: 0.05)
              : null,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(borderRadius),
              border: Border.all(
                color: borderColor ?? palette.sand.withValues(alpha: 0.9),
                width: borderWidth,
              ),
            ),
            child: padding != null
                ? Padding(padding: padding!, child: child)
                : child,
          ),
        ),
      ),
    );

    if (onTap != null) {
      // Web/desktop: курсор-рука и лёгкий отклик на hover.
      return MouseRegion(
        cursor: SystemMouseCursors.click,
        child: card,
      );
    }

    return card;
  }
}


/// Карточка с заголовком и контентом (как Trail card на HomePage).
class AppCardSection extends StatelessWidget {
  const AppCardSection({
    super.key,
    this.header,
    required this.child,
    this.footer,
    this.padding = const EdgeInsets.all(16),
    this.headerPadding,
    this.footerPadding,
    this.dividerColor,
  });

  final Widget? header;
  final Widget child;
  final Widget? footer;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? headerPadding;
  final EdgeInsetsGeometry? footerPadding;
  final Color? dividerColor;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (header != null) ...[
          Padding(
            padding: headerPadding ?? const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: header!,
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Divider(
              height: 1,
              thickness: 1,
              color:
                  dividerColor ?? palette.sand.withValues(alpha: 0.8),
            ),
          ),
          const SizedBox(height: 12),
        ],
        Padding(
          padding: padding,
          child: child,
        ),
        if (footer != null) ...[
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Divider(
              height: 1,
              thickness: 1,
              color:
                  dividerColor ?? palette.sand.withValues(alpha: 0.8),
            ),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: footerPadding ?? const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: footer!,
          ),
        ],
      ],
    );
  }
}


/// Карточка маршрута — журнальная обложка: фото во всю
/// ширину, внизу градиентный скрим с бейджами и названием.
class TrailCard extends StatefulWidget {
  const TrailCard({
    super.key,
    required this.title,
    required this.distance,
    required this.poiCount,
    this.imagePath,
    this.onTap,
    this.onFavoriteToggle,
    this.isFavorite = false,
    this.heroTag,
    this.walkingTime,
    this.listenedLabel,
    this.isBoat = false,
  });

  final String title;

  /// Длина маршрута в МЕТРАХ (см. `Trail.distance`).
  ///
  /// `null` — длина неизвестна, показывается «Длина неизвестна».
  final double? distance;

  final int poiCount;

  /// Обложка маршрута (полный путь ассета) — участвует в
  /// Hero-полёте на страницу маршрута, когда задан [heroTag].
  final String? imagePath;

  /// Тег Hero-полёта обложки в детали маршрута (4-й проход).
  final String? heroTag;
  final VoidCallback? onTap;
  final VoidCallback? onFavoriteToggle;
  final bool isFavorite;

  /// Расчётное время пешком («≈ 1 ч 20 мин», B2.3): из distance
  /// при 4 км/ч; null — не показывается.
  final String? walkingTime;

  /// «Прослушано N из M» (B2.3): тихая строка прогресса.
  final String? listenedLabel;

  /// Локация морская (П3, 12-й проход): рядом с «МАРШРУТ» —
  /// бейдж «ПО ВОДЕ».
  final bool isBoat;

  @override
  State<TrailCard> createState() => _TrailCardState();
}

class _TrailCardState extends State<TrailCard> {
  /// Импульс тапа по звезде: pop+haptic — только по действию
  /// пользователя, не при подгрузке избранного (P0-4).
  final ValueNotifier<int> _starTap = ValueNotifier<int>(0);

  @override
  void dispose() {
    _starTap.dispose();

    super.dispose();
  }

  /// Обложка карточки: фото с декодированием по ширине вьюпорта
  /// или бумажный плейсхолдер. Единый метод вместо двух копий
  /// Image.asset (с Hero и без).
  Widget _buildCover(BuildContext context) {
    final imagePath = widget.imagePath;

    return AspectRatio(
      aspectRatio: 16 / 10,
      child: imagePath != null
          ? Builder(
              builder: (context) => Image.asset(
                imagePath,
                fit: BoxFit.cover,
                width: double.infinity,
                // Обложка карточки не шире экрана: декодируем
                // не полноразмерное фото, а по ширине вьюпорта.
                cacheWidth: decodeWidthPx(
                  context,
                  MediaQuery.sizeOf(context).width,
                  oversample: 1,
                ),
                frameBuilder: skeletonFrameBuilder,
                errorBuilder: (context, error, stackTrace) {
                  return _placeholderImage();
                },
              ),
            )
          : _placeholderImage(),
    );
  }

  @override
  Widget build(BuildContext context) {

    final title = widget.title;

    final distance = widget.distance;

    final poiCount = widget.poiCount;

    final isFavorite = widget.isFavorite;

    final onTap = widget.onTap;

    final imagePath = widget.imagePath;

    final heroTag = widget.heroTag;

    // A11/B12: карточка читается скринридером как связная фраза;
    // container — чтобы звезда внутри оставалась отдельным узлом.
    return Semantics(
      label: 'Маршрут $title, ${formatTrailDistance(distance)}, '
          '$poiCount ${pluralRu(poiCount, 'место', 'места', 'мест')}',
      button: true,
      container: true,
      child: AppCard(
      onTap: onTap,
      padding: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.passthrough,
        children: [
          // Обложка участвует в Hero-полёте в детали маршрута
          // (4-й проход): полёт — только с реальным фото.
          // Оба случая строит один метод — без дублей Image.asset
          // (пункт 9 замечаний Sonnet).
          if (imagePath != null && heroTag != null)
            Hero(
              tag: heroTag,
              child: _buildCover(context),
            )
          else
            _buildCover(context),

          // Скрим для читаемости белого текста поверх фото.
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    stops: const [0.32, 1],
                    colors: [
                      AppColors.scrimInk.withValues(alpha: 0),
                      AppColors.scrimInk.withValues(alpha: 0.82),
                    ],
                  ),
                ),
              ),
            ),
          ),

          Positioned(
            top: 2,
            right: 2,
            child: Material(
              color: Colors.transparent,
              child: Tooltip(
                message: isFavorite
                    ? 'Убрать из избранного'
                    : 'В избранное',
                child: Semantics(
                  // Собственный узел с действием — звезда не
                  // «прячется» в озвучке карточки (P1-2, 7-й проход):
                  // container держит границу узла, иначе метка
                  // сливается с соседними текстами стека.
                  container: true,
                  button: true,
                  label: isFavorite
                      ? 'Убрать из избранного'
                      : 'В избранное',
                  child: InkWell(
                    onTap: () {
                      _starTap.value++;

                      widget.onFavoriteToggle?.call();
                    },
                    borderRadius: BorderRadius.circular(AppRadius.block),
                    // Тач-цель 44×44 — визуальный кружок меньше.
                    child: SizedBox(
                      width: 44,
                      height: 44,
                      child: Center(
                        child: AnimatedContainer(
                          duration: AppMotion.fast,
                          curve: AppMotion.curve,
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: isFavorite
                                ? AppColors.brandAccent
                                : AppColors.surfaceRaised
                                    .withValues(alpha: 0.9),
                            shape: BoxShape.circle,
                          ),
                          child: FavoriteStar(
                            filled: isFavorite,
                            size: 14,
                            filledColor: AppColors.accentOn,
                            tapSignal: _starTap,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),

          // Бейджи и название — на скриме у нижней кромки фото.
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 13),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.brandPrimary,
                          borderRadius: BorderRadius.circular(AppRadius.pill),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              LucideIcons.footprints,
                              size: 11,
                              color: AppColors.accentOn,
                            ),
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
                      // Морская локация (П3): маршрут — с воды.
                      if (widget.isBoat) ...[
                        const SizedBox(width: 8),
                        const BoatBadge(),
                      ],
                      const SizedBox(width: 8),
                      Flexible(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            // Белая полупрозрачная плашка поверх
                            // фото — роль onScrim, не голый белый
                            // (B1, 11-й проход).
                            color: AppColors.onScrim.withValues(alpha: 0.18),
                            borderRadius:
                                BorderRadius.circular(AppRadius.pill),
                          ),
                          child: Text(
                            // Единое форматирование метров — общий хелпер
                            // с TrailInfoSheet и страницей маршрута.
                            formatTrailDistance(distance).toUpperCase(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppText.label.copyWith(
                              letterSpacing: 0.6,
                              color: AppColors.onScrim.withValues(alpha: 0.92),
                            ),
                          ),
                        ),
                      ),
                      const Spacer(),
                      Text(
                        '$poiCount ${pluralRu(poiCount, 'место', 'места', 'мест')}',
                        style: AppText.caption.copyWith(
                          letterSpacing: 0.6,
                          color: AppColors.onScrim.withValues(alpha: 0.92),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpace.xs),
                  Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.cardTitle.copyWith(
                      height: 1.18,
                      color: AppColors.onScrim,
                    ),
                  ),
                  if (widget.walkingTime != null ||
                      widget.listenedLabel != null) ...[
                    const SizedBox(height: 5),
                    Text(
                      [
                        if (widget.walkingTime != null) widget.walkingTime!,
                        if (widget.listenedLabel != null)
                          widget.listenedLabel!,
                      ].join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.caption.copyWith(
                        letterSpacing: 0.3,
                        color: AppColors.onScrim.withValues(alpha: 0.85),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
      ),
    );
  }

  Widget _placeholderImage() {
    return Builder(builder: (context) {
      final palette = AppPalette.of(context);

      return Container(
        color: palette.sandLight,
        child: Center(
          child: Icon(
            LucideIcons.map,
            size: 32,
            color: palette.onSurface.withValues(alpha: 0.3),
          ),
        ),
      );
    });
  }

}
