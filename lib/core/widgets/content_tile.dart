import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/theme.dart';
import '../../features/favorites/presentation/widgets/favorite_star.dart';


/// Универсальная плитка контента для POI, Trail, Region.
///
/// Заменяет PoiTile, TrailTile и подобные. Поддерживает:
/// - leading (изображение/иконка)
/// - title + subtitle (опционально)
/// - trailing (chevron, значок избранного, действия)
/// - badge (номер POI, длина трека)
/// - isFavorite (звёздочка с анимацией)
/// - onTap / onLongPress
/// - compact / comfortable density
/// - divider (показывать или нет)
class ContentTile extends StatefulWidget {
  ContentTile({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.trailing,
    this.isFavorite = false,
    this.onFavoriteToggle,
    this.onTap,
    this.onLongPress,
    this.compact = false,
    this.showDivider = true,
    this.dividerIndent = 72,
    this.heroTag,
    this.semanticLabel,
    this.body,
  }) {
    // Ленивая сборка списков (A4) проверяется тестами по СОЗДАНИЮ
    // виджетов, а не монтированию: монтирование было ленивым и у
    // готовых списков, а вот сами виджеты строились в build целиком.
    debugCreatedCount++;
  }

  /// Сколько виджетов ContentTile создано с последнего сброса
  /// (только тесты).
  @visibleForTesting
  static int debugCreatedCount = 0;

  /// Сброс счётчика (тесты).
  @visibleForTesting
  static void debugResetCreatedCount() => debugCreatedCount = 0;

  final String title;
  final String? subtitle;
  final Widget? leading;
  final Widget? trailing;
  final bool isFavorite;
  final VoidCallback? onFavoriteToggle;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool compact;
  final bool showDivider;
  final double dividerIndent;
  final String? heroTag;
  final String? semanticLabel;

  /// Описание под подзаголовком (B2.4, 8-й проход): главная
  /// передаёт его только на широких экранах (≥600) — на телефоне
  /// плитка короткая: категория + аудио достаточно.
  final String? body;

  @override
  State<ContentTile> createState() => _ContentTileState();
}

class _ContentTileState extends State<ContentTile> {
  /// Импульс тапа по звезде: pop+haptic срабатывают только по
  /// действию пользователя, а не при подгрузке избранного
  /// (P0-4, 5-й проход).
  final ValueNotifier<int> _starTap = ValueNotifier<int>(0);

  @override
  void dispose() {
    _starTap.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final palette = AppPalette.of(context);

    final leadingWidget = widget.leading ??
        Container(
          width: widget.compact ? 48 : 56,
          height: widget.compact ? 48 : 56,
          decoration: BoxDecoration(
            color: palette.sandLight,
            borderRadius: BorderRadius.circular(AppRadius.thumb),
            border: Border.all(color: palette.sand, width: 1),
          ),
          child: Icon(
            LucideIcons.landmark,
            size: widget.compact ? 18 : 20,
            color: AppPalette.of(context).onSurfaceMuted,
          ),
        );

    final trailingWidget = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.onFavoriteToggle != null)
          IconButton(
            // Реальная заливка вместо цветового отличия; pop и
            // haptic — по импульсу тапа из onPressed (P0-4).
            icon: FavoriteStar(
              filled: widget.isFavorite,
              size: 21,
              tapSignal: _starTap,
            ),
            onPressed: () {
              _starTap.value++;

              widget.onFavoriteToggle?.call();
            },
            tooltip: widget.isFavorite ? 'Убрать из избранного' : 'В избранное',
            style: IconButton.styleFrom(
              minimumSize: const Size(44, 44),
              padding: EdgeInsets.zero,
              backgroundColor: widget.isFavorite
                  ? AppColors.brandAccent.withValues(alpha: 0.1)
                  : Colors.transparent,
            ),
          ),
        // Встроенный chevron — единый для всех плиток (P1-5):
        // самописные контейнеры-дубликаты удалены.
        if (widget.trailing != null) widget.trailing!,
        if (widget.trailing == null)
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              // Ролевая поверхность (B5).
              color: AppPalette.of(context).surfaceRaised,
              shape: BoxShape.circle,
              border: Border.all(
                color: AppPalette.of(context).sand,
                width: 1,
              ),
            ),
            child: Icon(
              LucideIcons.chevronRight,
              size: 14,
              color: AppPalette.of(context).onSurfaceMuted,
            ),
          ),
      ],
    );

    final tile = Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: widget.onTap,
        onLongPress: widget.onLongPress,
        borderRadius: BorderRadius.circular(AppRadius.tile),
        splashColor: AppColors.brandPrimary.withValues(alpha: 0.08),
        highlightColor: AppColors.brandPrimary.withValues(alpha: 0.04),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: 14,
            vertical: widget.compact ? 7 : 9,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (widget.heroTag != null)
                Hero(
                  tag: widget.heroTag!,
                  child: leadingWidget,
                )
              else
                leadingWidget,
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Flexible(
                          child: Text(
                            widget.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontSize: widget.compact ? 14 : 15,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -0.1,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (widget.subtitle != null) ...[
                      const SizedBox(height: 3),
                      Text(
                        widget.subtitle!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          height: 1.4,
                          color: AppPalette.of(context).onSurfaceMuted,
                        ),
                      ),
                    ],
                    if (widget.body != null) ...[
                      const SizedBox(height: 3),
                      Text(
                        widget.body!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          height: 1.4,
                          color: AppPalette.of(context).onSurfaceMuted,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              trailingWidget,
            ],
          ),
        ),
      ),
    );

    if (widget.semanticLabel != null) {
      return Semantics(
        label: widget.semanticLabel,
        button: true,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            tile,
            if (widget.showDivider)
              Divider(
                height: 1,
                thickness: 1,
                color: palette.sand.withValues(alpha: 0.7),
                indent: widget.dividerIndent,
              ),
          ],
        ),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        tile,
        if (widget.showDivider)
          Divider(
            height: 1,
            thickness: 1,
            color: palette.sand.withValues(alpha: 0.7),
            indent: widget.dividerIndent,
          ),
      ],
    );
  }
}
