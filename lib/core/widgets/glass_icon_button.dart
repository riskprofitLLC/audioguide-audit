import 'package:flutter/material.dart';

import '../../app/theme.dart';

/// Размер стеклянной кнопки.
enum GlassIconButtonSize {
  /// Стандартные контролы: карта, дерево, легенда.
  regular(44, 20, 12),

  /// «Главная» плавающая кнопка и другие крупные действия.
  primary(52, 22, 14);

  const GlassIconButtonSize(this.size, this.iconSize, this.padding);

  /// Сторона квадратной кнопки.
  final double size;

  /// Размер иконки внутри.
  final double iconSize;

  /// Внутренний отступ IconButton.
  final double padding;
}

/// Единая круглая «стеклянная» кнопка приложения (B1, 9-й проход).
///
/// Раньше четыре почти одинаковые кнопки расходились в размерах
/// (HomeButton 52, TreeNavigationButton 48, контролы карты 44).
/// Теперь: 44 — обычные контролы, 52 — «primary floating»; общие
/// рамка sand, тень [AppShadows.floating], тап-цель ≥44 и tooltip
/// с семантикой.
///
/// [floating] — парит над контентом (лёгкая «стеклянность»
/// полупрозрачного фона + тень); встроенные в шапку кнопки
/// передают false.
class GlassIconButton extends StatelessWidget {
  const GlassIconButton({
    super.key,
    required this.tooltip,
    required this.onTap,
    this.icon,
    this.child,
    this.size = GlassIconButtonSize.regular,
    this.floating = true,
    this.isPrimary = false,
    this.loading = false,
    this.active = false,
    this.semanticLabel,
  });

  /// Подсказка (tooltip + Semantics).
  final String tooltip;

  /// Иконка (если [child] не задан).
  final IconData? icon;

  /// Полностью свой контент (например, звезда избранного).
  final Widget? child;

  /// Геометрия кнопки: 44 обычная, 52 — с [isPrimary].
  final GlassIconButtonSize size;

  /// Парит над контентом: тень + полупрозрачная «стеклянность».
  final bool floating;

  /// Крупная плавающая кнопка (52 px): «Домой».
  final bool isPrimary;

  /// Вместо иконки — индикатор, тапы игнорируются (поиск GPS).
  final bool loading;

  /// Активное состояние (B2, 17-й проход): заливка depth и
  /// светлая иконка — «следую за мной» на кнопке GPS.
  final bool active;

  /// Метка для скринридера; по умолчанию — [tooltip].
  final String? semanticLabel;

  /// Тап (null — кнопка выключена).
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final geometry =
        isPrimary ? GlassIconButtonSize.primary : size;

    final palette = AppPalette.of(context);

    // Стекло кнопки — ролевое (B5): светлый лист/тёмная плашка.
    final glass = palette.surfaceRaised;

    // Активная кнопка залита бирюзой глубины (B2, 17-й проход).
    final background = active ? AppColors.depth : glass;

    final button = Material(
      color: active
          ? background
          : (floating
              ? glass.withValues(alpha: 0.94)
              : glass),
      elevation: 0,
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        // Тапы НЕ гасятся спиннером (A5, 17-й проход): кнопка GPS
        // в поиске отменяется повторным тапом — решает сам onTap
        // (_locateMe смотрит на _locating).
        onTap: onTap,
        child: Container(
          width: geometry.size,
          height: geometry.size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: palette.sand,
              width: 1,
            ),
          ),
          alignment: Alignment.center,
          child: loading
              ? SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: palette.onSurface.withValues(alpha: 0.72),
                  ),
                )
              : child ??
                  Icon(
                    icon,
                    size: geometry.iconSize,
                    color: active
                        ? AppColors.accentOn
                        : palette.onSurface.withValues(alpha: 0.72),
                  ),
        ),
      ),
    );

    final withTooltip = Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        label: semanticLabel ?? tooltip,
        child: button,
      ),
    );

    if (!floating) {
      return withTooltip;
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: AppShadows.floating(palette.onSurface),
      ),
      child: withTooltip,
    );
  }
}
