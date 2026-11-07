import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../app/theme.dart';

/// Бейдж «ПО ВОДЕ» (П3, 12-й проход): локация осматривается
/// с воды (манифест `transport: "boat"`). Единый для карточки
/// маршрута, страницы деталей и шторки на карте.
class BoatBadge extends StatelessWidget {
  const BoatBadge({super.key});

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);

    // B1/B2: роли палитры — ночью светлый бейдж с тёмной иконкой
    // onInfo (белый accentOn на светло-голубой info давал ~2:1).
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: palette.info,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            LucideIcons.sailboat,
            size: 12,
            color: palette.onInfo,
          ),
          const SizedBox(width: 5),
          Text(
            'ПО ВОДЕ',
            style: AppText.label.copyWith(
              color: palette.onInfo,
              letterSpacing: 0.8,
            ),
          ),
        ],
      ),
    );
  }
}
