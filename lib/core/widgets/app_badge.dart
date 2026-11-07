import 'package:flutter/material.dart';

import '../../app/theme.dart';

/// Вариант бейджа «Атласа»: заливка задаёт роль, подпись — токен.
enum AppBadgeVariant {
  /// Заливка информационным акцентом (бирюза): номер точки,
  /// «МАРШРУТ», «ПО ВОДЕ».
  info,

  /// Песочная плашка с волосяной рамкой: категория, счётчики.
  sand,

  /// Полупрозрачная светлая плашка ПОВЕРХ ФОТО: дистанция,
  /// счётчик мест. Цвет — осознанно постоянная роль onScrim.
  scrim,
}

/// Единый бейдж системы (было три разные вёрстки: детали POI,
/// шторка на карте и миниатюра списка).
///
/// Одна геометрия (padding 8×3, радиус [AppRadius.pill]), один
/// набор токенов: [AppText.badge] для читаемых слов, [AppText.label]
/// для CAPS-подписей. Разные варианты отличаются только заливкой.
class AppBadge extends StatelessWidget {
  const AppBadge({
    super.key,
    required this.label,
    this.variant = AppBadgeVariant.sand,
    this.icon,
    this.leading,
    this.caps = false,
    this.semanticLabel,
    this.border,
  });

  /// Подпись бейджа.
  final String label;

  final AppBadgeVariant variant;

  /// Ведущий глиф (следы, парус) — рисуется цветом подписи.
  final IconData? icon;

  /// Произвольный ведущий элемент (глиф категории карты).
  final Widget? leading;

  /// CAPS-подпись («МАРШРУТ», «ПО ВОДЕ»): токен [AppText.label]
  /// (11 px допустим только для CAPS/цифр).
  final bool caps;

  /// Метка для скринридера (по умолчанию — сама подпись).
  final String? semanticLabel;

  /// Волосяная рамка поверх заливки (sand-вариант).
  final bool? border;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);

    final Color background;
    final Color foreground;
    var showBorder = border;

    switch (variant) {
      case AppBadgeVariant.info:
        background = palette.info;
        foreground = palette.onInfo;
      case AppBadgeVariant.sand:
        background = palette.sandLight;
        foreground = palette.onSurface.withValues(alpha: 0.72);
        showBorder ??= true;
      case AppBadgeVariant.scrim:
        background = AppColors.onScrim.withValues(alpha: 0.18);
        foreground = AppColors.onScrim.withValues(alpha: 0.92);
    }

    final style = caps
        ? AppText.label.copyWith(color: foreground, letterSpacing: 0.8)
        : AppText.badge.copyWith(color: foreground);

    return Semantics(
      label: semanticLabel,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(AppRadius.pill),
          border: showBorder == true
              ? Border.all(
                  color: variant == AppBadgeVariant.scrim
                      ? AppColors.onScrim.withValues(alpha: 0.18)
                      : palette.sand,
                  width: 1,
                )
              : null,
        ),
        child: icon == null && leading == null
            ? Text(label, maxLines: 1, style: style)
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (leading != null)
                    leading!
                  else
                    Icon(icon, size: caps ? 11 : 12, color: foreground),
                  const SizedBox(width: 5),
                  Text(label, maxLines: 1, style: style),
                ],
              ),
      ),
    );
  }
}
