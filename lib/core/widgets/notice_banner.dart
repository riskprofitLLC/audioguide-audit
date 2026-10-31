import 'package:flutter/material.dart';

import '../../app/theme.dart';

/// Вариант баннера-уведомления.
enum NoticeBannerVariant {
  /// Нейтральное замечание («В разработке»).
  info,

  /// Предупреждение («Пешие маршруты запрещены»).
  warning,

  /// Ошибка (баннер сбоя инициализации).
  error,
}

/// Единый баннер-уведомление (B2, 11-й проход): глиф в квадрате,
/// заголовок, текст и опциональный футер (действия, «Подробнее»).
///
/// Заменяет четыре самодельных баннера — ошибку инициализации
/// главной, запрет пеших маршрутов (главная и карта) и заглушку
/// «В разработке»: одна вёрстка, три варианта окраски.
///
/// [compact] — уменьшенный вариант для плавающих плашек на карте
/// (квадрат глифа и подписи меньше, радиус [AppRadius.tile]);
/// [floating] добавляет «плавающую» тень [AppShadows.floating]
/// вместо мягкой карточной. [footer] — произвольный блок под
/// текстом (кнопка «Повторить», сворачиваемая деталь ошибки).
class NoticeBanner extends StatelessWidget {
  const NoticeBanner({
    super.key,
    this.variant = NoticeBannerVariant.info,
    required this.icon,
    required this.title,
    required this.message,
    this.footer,
    this.compact = false,
    this.floating = false,
  });

  final NoticeBannerVariant variant;

  final IconData icon;

  final String title;

  final String message;

  final Widget? footer;

  final bool compact;

  final bool floating;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Ролевые поверхности баннера (B5): светлая тема — те же
    // белый лист и песочная рамка, тёмная — тёмные ступени.
    final palette = AppPalette.of(context);

    final isError = variant == NoticeBannerVariant.error;

    // Квадрат глифа: песок (info) / тёплый тинт (warning) /
    // светлая плашка (error — на фоне errorContainer).
    final squareColor = switch (variant) {
      NoticeBannerVariant.info => palette.sandLight,
      NoticeBannerVariant.warning => AppColors.alertTint,
      NoticeBannerVariant.error =>
        AppColors.surfaceRaised.withValues(alpha: 0.55),
    };

    final iconColor = switch (variant) {
      NoticeBannerVariant.info => palette.onSurface,
      NoticeBannerVariant.warning => AppColors.alertInk,
      NoticeBannerVariant.error => theme.colorScheme.error,
    };

    // Текст: на errorContainer — семантический onErrorContainer,
    // прочие — чернильные на бумаге.
    final titleColor =
        isError ? theme.colorScheme.onErrorContainer
            : palette.onSurface;

    final messageColor =
        isError ? theme.colorScheme.onErrorContainer : null;

    final squareSize = compact ? 28.0 : 32.0;

    final squareRadius = compact ? 7.0 : 10.0;

    final iconSize = compact ? 14.0 : 16.0;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: isError
            ? theme.colorScheme.errorContainer
            : palette.surfaceRaised,
        borderRadius: BorderRadius.circular(
          compact ? AppRadius.tile : AppRadius.card,
        ),
        border: Border.all(
          color: isError
              ? theme.colorScheme.error
              : palette.sand.withValues(alpha: 0.9),
        ),
        boxShadow: floating
            ? AppShadows.floating(palette.onSurface)
            : AppShadows.card(palette.onSurface),
      ),
      child: Padding(
        padding: compact
            ? const EdgeInsets.symmetric(horizontal: 12, vertical: 8)
            : const EdgeInsets.all(AppSpace.m),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: squareSize,
              height: squareSize,
              decoration: BoxDecoration(
                color: squareColor,
                borderRadius: BorderRadius.circular(squareRadius),
              ),
              child: Icon(
                icon,
                size: iconSize,
                color: iconColor,
              ),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontSize: compact ? 11 : 12,
                      fontWeight: FontWeight.w800,
                      letterSpacing: compact ? 0.5 : 0.6,
                      color: titleColor,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    message,
                    style: theme.textTheme.bodySmall?.copyWith(
                      height: compact ? 1.35 : 1.45,
                      fontSize: compact ? 11 : null,
                      color: messageColor,
                    ),
                  ),
                  if (footer != null) ...[
                    const SizedBox(height: AppSpace.xs),
                    footer!,
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
