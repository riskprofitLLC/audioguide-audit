import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../app/theme.dart';

/// Шапка главного экрана — титульная страница атласа.
///
/// Редизайн «Атлас»: без карточки и градусных тиков — чистый
/// текст на фоне листа, тонкая иконка-компас, крупное serif-
/// название региона и много воздуха.
class IslandHeader extends StatelessWidget {

  const IslandHeader({
    super.key,
    required this.islandName,
    this.eyebrow = 'СРЕДИЗЕМНОЕ МОРЕ · ТУРЦИЯ',
    this.version,
    this.action,
  });


  final String islandName;

  /// Eyebrow-подпись — море и страна из манифеста региона.
  final String eyebrow;

  final int? version;

  final Widget? action;


  @override
  Widget build(BuildContext context) {

    final palette = AppPalette.of(context);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [

        Icon(
          LucideIcons.compass,
          size: 22,
          color: palette.info,
        ),

        const SizedBox(width: AppSpace.s),

        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [

              // Eyebrow — море и страна (из манифеста региона).
              Text(
                eyebrow,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppText.eyebrow.copyWith(
                  letterSpacing: 1.6,
                  color: palette.info,
                ),
              ),

              const SizedBox(height: AppSpace.xs),

              // Название региона — обложка атласа, крупный Prata.
              Text(
                islandName,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppText.display.copyWith(
                  height: 1.05,
                  color: palette.onSurface,
                ),
              ),

              const SizedBox(height: AppSpace.s),

              // Версия пакета — «издание атласа».
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: palette.sandLight,
                  borderRadius: BorderRadius.circular(AppRadius.chip),
                  border: Border.all(
                    color: palette.sand,
                    width: 1,
                  ),
                ),
                child: Text(
                  version != null ? 'Издание $version' : 'офлайн-пакет',
                  style: AppText.label.copyWith(
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.4,
                    color: palette.onSurface.withValues(alpha: 0.72),
                  ),
                ),
              ),
            ],
          ),
        ),

        if (action != null) ...[
          const SizedBox(width: AppSpace.xs),
          action!,
        ],
      ],
    );
  }
}
