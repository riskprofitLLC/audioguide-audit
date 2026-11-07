import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/theme.dart';

/// Единый чип «Атласа» (было четыре разных вёрстки: лента регионов,
/// фильтры поиска, мета-чипы деталей и чипы легенды карты).
///
/// Один язык состояния: выбранный — заливка [AppPalette.info] с
/// текстом [AppPalette.onInfo] (не accentOn: ночью info светлая и
/// белый текст давал ~2:1), невыбранный — поверхность с волосяной
/// рамкой. Пилюля, тап-цель 44, семантика button+selected.
class AppChip extends StatelessWidget {
  const AppChip({
    super.key,
    required this.label,
    this.icon,
    this.leading,
    this.selected = false,
    this.onTap,
    this.semanticLabel,
    this.check = false,
    this.dense = false,
    this.tall = false,
    this.fill,
    this.textColor,
  });

  /// Подпись чипа.
  final String label;

  /// Ведущий глиф (иконка состояния/категории).
  final IconData? icon;

  /// Произвольный ведущий элемент (образец категории карты).
  final Widget? leading;

  /// Выбранное состояние (заливка акцентом).
  final bool selected;

  /// Обработчик тапа: `null` — чип статичен (мета-подпись).
  final VoidCallback? onTap;

  /// Метка для скринридера.
  final String? semanticLabel;

  /// Галочка успеха («прослушано») вместо ведущего глифа.
  final bool check;

  /// Компактный вариант: мета-подписи деталей (12 px, авто-высота).
  final bool dense;


  /// Крупный вариант: ленты переключателей главной (регионы и
  /// локации) — пилюля вырастает до ~34 px, подпись до
  /// [AppText.button]. Тап-цель остаётся 44.
  final bool tall;

  /// Переопределение заливки выбранного состояния.
  final Color? fill;

  /// Переопределение цвета текста выбранного состояния.
  final Color? textColor;

  bool get _tappable => onTap != null;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);

    final activeFill = fill ?? palette.info;

    final activeText = textColor ?? palette.onInfo;

    final background = selected ? activeFill : palette.surfaceRaised;

    final foreground = selected ? activeText : palette.onSurface;

    final leadColor =
        selected ? activeText : (check ? palette.success : palette.onSurfaceMuted);

    final style = dense
        ? AppText.caption.copyWith(
            fontWeight: FontWeight.w700,
            letterSpacing: 0.3,
            color: leadColor,
          )
        : tall
            ? AppText.button.copyWith(color: foreground)
            : AppText.chip.copyWith(
                color: foreground,
                fontWeight: selected ? FontWeight.w800 : FontWeight.w700,
                letterSpacing: 0.15,
              );

    final content = Container(
      padding: EdgeInsets.symmetric(
        horizontal: dense ? 10 : (tall ? 18 : 14),
        vertical: dense ? 5 : (tall ? 9 : 0),
      ),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(
          color: selected ? activeFill : palette.sand.withValues(alpha: 0.9),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (leading != null) ...[
            leading!,
            const SizedBox(width: 6),
          ],
          if (icon != null || check) ...[
            Icon(
              check ? Icons.check : icon,
              size: dense ? 13 : (tall ? 17 : 15),
              color: leadColor,
            ),
            const SizedBox(width: 6),
          ],
          // Длинная подпись режется эллипсисом, а не переполняет
          // пилюлю при textScale 1.6 на узких экранах.
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: style,
            ),
          ),
        ],
      ),
    );

    if (!_tappable) {
      return content;
    }

    return Semantics(
      button: true,
      selected: selected,
      label: semanticLabel,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.pill),
          onTap: () {
            HapticFeedback.selectionClick();

            onTap!();
          },
          // Тап-цель 44 при визуальной высоте 36 (dense — авто).
          child: SizedBox(
            height: dense ? null : 44,
            child: Center(child: content),
          ),
        ),
      ),
    );
  }
}
