import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/theme.dart';

/// Тон плавающей пилюли (D2, замечание Sonnet): определяет цвет
/// ведущего круга с иконкой.
enum FloatingPillTone {
  /// Бирюза глубины — действия и статусы «нормально».
  info,

  /// Сигнальный — предупреждения (запрет, потеря сигнала).
  warning,

  /// Песок — нейтральные плашки без акцента.
  neutral,
}

/// Единый компонент плавающих «пилюль» (D2, замечание Sonnet).
///
/// Один силуэт для всех плавающих элементов поверх контента и
/// карты: радиус [AppRadius.pill], тень [AppShadows.floating],
/// «стекло» surfaceRaised @0.96, ведущая иконка в круге 36,
/// тап-цель ≥44, Semantics. Используют: плашка статуса
/// геолокации, чип ближайшей точки, «Рядом», погода,
/// «К описанию», мини-плеер.
///
/// [leading] — произвольный ведущий элемент (обложка мини-плеера,
/// стрелка компаса); без него строится круг с [icon].
///
/// Появление — Reduce Motion-aware: [FloatingPill.show] анимирует
/// подъём+фейд, статичный [FloatingPill] — без анимации.
class FloatingPill extends StatelessWidget {
  const FloatingPill({
    super.key,
    this.icon,
    this.leading,
    this.tone = FloatingPillTone.info,
    required this.child,
    this.onTap,
    this.semanticsLabel,
    this.tooltip,
    this.padding = const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    this.gap = 10,
    this.background,
  });

  /// Иконка в ведущем круге (когда [leading] не задан).
  final IconData? icon;

  /// Произвольный ведущий элемент вместо круга с [icon].
  final Widget? leading;

  final FloatingPillTone tone;

  /// Содержимое пилюли (подпись, кнопки).
  final Widget child;

  /// Тап по пилюле; null — пилюля не интерактивна.
  final VoidCallback? onTap;

  /// Семантика (container+button): отдельный узел для скринридера.
  final String? semanticsLabel;

  /// Тултип (не дублируется в семантику — она уже несёт текст).
  final String? tooltip;

  /// Внутренние отступы (высота тап-цели держится ведущим кругом
  /// 36 + vertical 4*2 = 44).
  final EdgeInsetsGeometry padding;

  /// Зазор между ведущим элементом и содержимым.
  final double gap;

  /// Фон пилюли (D2): `null` — «стекло» surfaceRaised @0.96;
  /// задан — сплошная заливка (например, «К описанию» — бирюзовая
  /// кнопка-акцент).
  final Color? background;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);

    final (iconBackground, iconColor) = switch (tone) {
      FloatingPillTone.info => (palette.info, palette.accentOn),
      FloatingPillTone.warning => (palette.accent, palette.accentOn),
      FloatingPillTone.neutral => (palette.sandLight, palette.info),
    };

    final leadingWidget = leading ??
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: iconBackground,
            shape: BoxShape.circle,
          ),
          child: Icon(
            icon ?? LucideIcons.info,
            size: 16,
            color: iconColor,
          ),
        );

    Widget pill = DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.pill),
        boxShadow: AppShadows.floating(palette.onSurface),
      ),
      child: Material(
        // «Стекло» — полупрозрачная поверхность над картой;
        // явный фон — сплошная заливка (кнопки-акценты).
        color: background ?? palette.surfaceRaised.withValues(alpha: 0.96),
        elevation: 0,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.pill),
          onTap: onTap,
          // Тап-цель ≥44 по высоте — общий стандарт пилюль.
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 44),
            child: Padding(
              padding: padding,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  leadingWidget,
                  SizedBox(width: gap),
                  Flexible(child: child),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    if (tooltip != null) {
      pill = Tooltip(
        message: tooltip!,
        excludeFromSemantics: true,
        child: pill,
      );
    }

    if (semanticsLabel != null) {
      pill = Semantics(
        button: onTap != null,
        container: true,
        label: semanticsLabel,
        child: pill,
      );
    }

    return pill;
  }
}

/// Появление пилюли (D2): подъём + фейд, Reduce Motion — мгновенно.
/// Используется вместо AnimatedSwitcher-обёрток на местах.
class FloatingPillShow extends StatelessWidget {
  const FloatingPillShow({
    super.key,
    required this.visible,
    required this.child,
  });

  final bool visible;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final reduceMotion =
        MediaQuery.maybeDisableAnimationsOf(context) == true;

    return IgnorePointer(
      ignoring: !visible,
      child: AnimatedOpacity(
        opacity: visible ? 1 : 0,
        duration: reduceMotion ? Duration.zero : AppMotion.fast,
        curve: AppMotion.curve,
        child: AnimatedSlide(
          offset: visible ? Offset.zero : const Offset(0, 0.18),
          duration: reduceMotion ? Duration.zero : AppMotion.fast,
          curve: AppMotion.curve,
          child: child,
        ),
      ),
    );
  }
}
