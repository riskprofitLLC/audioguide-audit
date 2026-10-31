import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/theme.dart';

/// Радио-строка выбора режима (D2, замечания Sonnet): единый
/// виджет для настроек — прежде «Автогид» и «Тема» держали две
/// идентичные копии разметки. Тап-цель 44, выбранная строка — с
/// глифом-галочкой, Semantics button + selected.
class RadioRowTile extends StatelessWidget {
  const RadioRowTile({
    super.key,
    required this.semanticLabel,
    required this.label,
    required this.hint,
    required this.selected,
    required this.onSelect,
  });

  /// Полная метка для скринридера («Автогид: всегда» / «Тема: тёмная»).
  final String semanticLabel;

  /// Название режима.
  final String label;

  /// Короткое пояснение под названием.
  final String hint;

  /// Выбрана ли строка.
  final bool selected;

  /// Тап по строке.
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) {

    final palette = AppPalette.of(context);

    return Semantics(
      container: true,
      button: true,
      selected: selected,
      label: semanticLabel,
      child: SizedBox(
        height: 44,
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.chip),
          onTap: onSelect,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              children: [
                SizedBox(
                  width: 22,
                  height: 22,
                  child: selected
                      ? Icon(
                          LucideIcons.circleCheck,
                          size: 20,
                          color: palette.info,
                        )
                      : Icon(
                          LucideIcons.circle,
                          size: 18,
                          color: palette.outline.withValues(alpha: 0.5),
                        ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: AppText.body.copyWith(
                          fontWeight: selected
                              ? FontWeight.w800
                              : FontWeight.w700,
                          color: selected
                              ? palette.onSurface
                              : palette.onSurfaceMuted,
                        ),
                      ),
                      Text(
                        hint,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.label.copyWith(
                          color: palette.onSurfaceMuted,
                        ),
                      ),
                    ],
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
