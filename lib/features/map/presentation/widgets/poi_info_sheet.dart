import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/theme.dart';
import '../../../../core/widgets/expandable_text.dart';
import '../../../../core/widgets/info_sheet_scaffold.dart';
import '../../../../features/poi/models/poi.dart';
import '../../../../features/poi/utils/poi_category.dart';
import '../../../audio/presentation/widgets/audio_guide_player.dart';
import '../../../content/presentation/widgets/image_gallery.dart';
import '../../../favorites/presentation/widgets/favorite_button.dart';

/// Информационная панель точки интереса.
///
/// Фото, название, описание, кнопка голосового гида и звезда
/// «в избранное» (как на странице деталей POI).

class PoiInfoSheet extends ConsumerWidget {
  const PoiInfoSheet({
    super.key,
    required this.poi,
    required this.islandId,
    this.scrollController,
  });

  final Poi poi;

  final String islandId;

  /// Контроллер прокрутки DraggableScrollableSheet (1d, 12-й
  /// проход). Передан — шторка живёт в режиме «со стопами»:
  /// без капа 70%, размером управляет лист. `null` — прежний
  /// автономный режим с капом.
  final ScrollController? scrollController;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    return InfoSheetScaffold(
      scrollController: scrollController,
      children: [
        const SizedBox(height: 16),

        ImageGallery(
          imagePaths: poi.imagePaths,
          videoPath: poi.videoPath,
          islandId: islandId,
          height: 176,
          borderRadius: 14,
          // Как на деталях POI (B3.6): у точек с 40–69
          // фото карусель в шторке листать нереально —
          // 12 кадров + плитка «Все фото (N)».
          maxCarouselFrames: 12,
        ),

        const SizedBox(height: 16),

        // Бейджи (номер + категория) — Wrap НАД заголовком:
        // на 360 px в одной строке с названием и звездой им
        // оставалось ~110 px, и название переносилось на
        // 4–5 строк (P1-2, 6-й проход).
        if (poi.number != null || poi.category != null) ...[
          Wrap(
            spacing: 10,
            runSpacing: 6,
            children: [
              if (poi.number != null)
                // Пилюля номера — тот же язык бейджей, что и
                // оверлей на миниатюрах списков.
                Semantics(
                  label: 'Точка ${poi.number}',
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.depth,
                      borderRadius:
                          BorderRadius.circular(AppRadius.pill),
                    ),
                    child: Text(
                      '${poi.number}',
                      style: AppText.caption.copyWith(
                        height: 1,
                        fontWeight: FontWeight.w800,
                        color: AppColors.accentOn,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ),
                ),

              // Бейдж категории + маленький глиф — тот же,
              // что в маркере на карте (P1-3).
              if (poi.category != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: AppPalette.of(context).sandLight,
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                    border: Border.all(
                        color: AppPalette.of(context).sand,
                        width: 1),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Image.asset(
                        poiCategoryGlyph(poi.category),
                        width: 12,
                        height: 12,
                        color: poiCategoryGlyphColor(poi.category),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        poiCategoryLabel(poi.category),
                        style: AppText.label.copyWith(
                          fontWeight: FontWeight.w700,
                          color: AppPalette.of(context)
                              .onSurface
                              .withValues(alpha: 0.72),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),

          const SizedBox(height: 8),
        ],

        // Название + звезда «в избранное» — вторая строка:
        // названию достаётся вся ширина (P1-2).
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                poi.title,
                style: AppText.h2.copyWith(
                ),
              ),
            ),

            const SizedBox(width: 8),

            // Звезда прижата к верхней кромке строки — выровнена
            // с первой строкой названия.
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: FavoriteButton(
                itemId: poi.id,
                islandId: islandId,
              ),
            ),
          ],
        ),

        if (poi.audioPath != null) ...[
          const SizedBox(height: 16),

          AudioGuidePlayer(
            assetPath: poi.audioAssetPath(islandId),
            audioMs: poi.audioMs,
            wave: poi.wave,
          ),
        ],

        if (poi.description != null) ...[
          const SizedBox(height: 16),

          ExpandableText(
            text: poi.description!,
            collapsedLines: 4,
            style: theme.textTheme.bodyMedium,
          ),
        ],

        const SizedBox(height: 16),

        // Полная страница точки: шторка закрывается, плеер
        // останавливает код закрытия шторки (map_taps),
        // детали открываются поверх карты (A11).
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton.tonal(
            onPressed: () {
              Navigator.of(context).pop();

              context.push('/poi/${poi.id}?island=$islandId');
            },
            child: const Text('Подробнее'),
          ),
        ),
      ],
    );
  }
}
