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

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.depth,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            LucideIcons.sailboat,
            size: 12,
            color: AppColors.accentOn,
          ),
          const SizedBox(width: 5),
          Text(
            'ПО ВОДЕ',
            style: AppText.label.copyWith(
              color: AppColors.accentOn,
              letterSpacing: 0.8,
            ),
          ),
        ],
      ),
    );
  }
}
