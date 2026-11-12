import 'package:flutter/material.dart';

import '../../app/theme.dart';


/// Заголовок секции с сигнальным ромбом, счётчиком и действием справа.
///
/// Варианты:
/// - `compact` — для вложенных секций (Manrope)
/// - `comfortable` — основной заголовок секции (Prata, «журнальный»)
enum SectionTitleVariant { compact, comfortable }

class SectionTitle extends StatelessWidget {
  const SectionTitle({
    super.key,
    required this.title,
    this.count,
    this.action,
    this.variant = SectionTitleVariant.comfortable,
    this.showDiamond = true,
  });

  final String title;
  final int? count;
  final Widget? action;
  final SectionTitleVariant variant;
  final bool showDiamond;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);

    final isCompact = variant == SectionTitleVariant.compact;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Flexible(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (showDiamond) ...[
                Transform.rotate(
                  angle: 0.785398,
                  child: Container(
                    width: isCompact ? 5 : 7,
                    height: isCompact ? 5 : 7,
                    decoration: BoxDecoration(
                      color: palette.accent,
                      borderRadius: BorderRadius.only(
                        topLeft: Radius.circular(isCompact ? 1 : 1.5),
                        topRight: Radius.circular(isCompact ? 1 : 1.5),
                      ),
                    ),
                  ),
                ),
                SizedBox(width: isCompact ? 7 : 10),
              ],
              Flexible(
                child: Text(
                  title,
                  overflow: TextOverflow.ellipsis,
                  // Крупная секция — серифный Prata без веса,
                  // компактная — Manrope.
                  style: isCompact
                      ? AppText.sectionTitle.copyWith(
                          color: palette.onSurface,
                        )
                      : AppText.h2.copyWith(
                          color: palette.onSurface,
                        ),
                ),
              ),
              if (count != null) ...[
                const SizedBox(width: AppSpace.xs),
                Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: isCompact ? 7 : 8,
                    vertical: isCompact ? 1.5 : 2.5,
                  ),
                  decoration: BoxDecoration(
                    color: palette.sandLight,
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                    border: Border.all(color: palette.sand, width: 1),
                  ),
                  child: Text(
                    '$count',
                    // Счётчик — читаемые цифры: минимум 12 px
                    // (было 9/10 — мельче допустимого порога).
                    style: AppText.badge.copyWith(
                      color: palette.onSurface.withValues(alpha: 0.72),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        ?action,
      ],
    );
  }
}


/// Простой разделитель с тонкой линией.
class AppDivider extends StatelessWidget {
  const AppDivider({
    super.key,
    this.height = 1,
    this.color,
    this.indent = 0,
    this.endIndent = 0,
  });

  final double height;
  final Color? color;
  final double indent;
  final double endIndent;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);

    return Divider(
      height: height,
      thickness: height,
      color: color ?? palette.sand.withValues(alpha: 0.8),
      indent: indent,
      endIndent: endIndent,
    );
  }
}
