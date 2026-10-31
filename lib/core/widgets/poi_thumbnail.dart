import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/theme.dart';
import '../../core/utils/decode_size.dart';
import 'skeleton.dart';

/// Миниатюра точки в списках (главная, избранное): фото или
/// иконка-фолбэк в тёплой рамке + бейдж номера маршрутной точки
/// в углу. Единый язык бейджей вместо трёх копий разной вёрстки.
class PoiThumbnail extends StatelessWidget {
  const PoiThumbnail({
    super.key,
    this.imagePath,
    this.number,
    this.size = 52,
  });

  /// Полный путь к первому фото точки; `null` — иконка-фолбэк.
  final String? imagePath;

  /// Номер маршрутной точки (бейдж в правом нижнем углу).
  final int? number;

  /// Сторона миниатюры (52 — списки, 56 — избранное).
  final double size;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);

    return Stack(
      alignment: Alignment.bottomRight,
      children: [
        Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: palette.sandLight,
            borderRadius: BorderRadius.circular(AppRadius.thumb),
            border: Border.all(color: palette.sand, width: 1),
          ),
          clipBehavior: Clip.antiAlias,
          child: imagePath == null
              ? Icon(
                  LucideIcons.landmark,
                  size: size <= 48 ? 18 : 20,
                  color: AppPalette.of(context).onSurfaceMuted,
                )
              : Image.asset(
                  imagePath!,
                  fit: BoxFit.cover,
                  // Миниатюра не декодирует полноразмерное фото
                  // (~1200 px) — режем по ширине.
                  cacheWidth: decodeWidthPx(context, size),
                  // B4 (10-й проход): без прыжков раскладки —
                  // скелетон до первого кадра (фон-заглушка уже
                  // держит геометрию, скелетон добавляет шиммер).
                  frameBuilder: skeletonFrameBuilder,
                  errorBuilder: (context, error, stackTrace) {
                    return Icon(
                      LucideIcons.landmark,
                      size: size <= 48 ? 18 : 20,
                      color: AppPalette.of(context).onSurfaceMuted,
                    );
                  },
                ),
        ),

        // Номер маршрутной точки — оверлеем в углу миниатюры.
        if (number != null)
          Semantics(
            label: 'Точка $number',
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.depth,
                borderRadius: BorderRadius.circular(AppRadius.pill),
                border: Border.all(color: palette.surfaceRaised, width: 1.2),
              ),
              child: Text(
                '$number',
                style: AppText.label.copyWith(
                  height: 1,
                  fontWeight: FontWeight.w800,
                  color: AppColors.accentOn,
                  letterSpacing: 0.2,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
