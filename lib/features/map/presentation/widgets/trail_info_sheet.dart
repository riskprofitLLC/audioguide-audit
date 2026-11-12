import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../app/theme.dart';
import '../../../../core/utils/plural.dart';
import '../../../../core/widgets/expandable_text.dart';
import '../../../../core/widgets/info_sheet_scaffold.dart';
import '../../../../features/trails/models/trail.dart';
import '../../../../features/trails/presentation/widgets/boat_badge.dart';
import '../../../../features/trails/utils/format_distance.dart';
import '../../../../features/trails/utils/elevation_stats.dart';
import '../../../content/presentation/widgets/image_gallery.dart';
import '../../../favorites/presentation/widgets/favorite_button.dart';

/// Информационная панель маршрута.

class TrailInfoSheet extends StatelessWidget {
  const TrailInfoSheet({
    super.key,
    required this.trail,
    required this.islandId,
    required this.imagePaths,
    required this.poiCount,
    required this.cascadeKeys,
    this.scrollController,
    this.isBoat = false,
  });

  final Trail trail;

  /// Остров, к которому относится маршрут (для загрузки фото).
  final String islandId;

  /// Фотографии маршрута — это все фотографии всех
  /// достопримечательностей острова вместе; отдельных
  /// фото у самого маршрута нет.
  final List<String> imagePaths;

  /// Число точек маршрута — для подписи «N мест» (P1-3).
  final int poiCount;

  /// Ключи избранных точек маршрута: звезда маршрута включает
  /// их каскадом, как на странице деталей (P1-3).
  final Iterable<String> cascadeKeys;

  /// Контроллер прокрутки DraggableScrollableSheet (1d, 12-й
  /// проход): передан — режим без капа 70%, размером управляет
  /// лист; `null` — прежний автономный режим.
  final ScrollController? scrollController;

  /// Морская локация (П3, 12-й проход): бейдж «ПО ВОДЕ».
  final bool isBoat;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Рельеф трека (П5): сводка по точкам с высотами.
    final elevationStats = computeElevationStatsSegments(trail.segments);

    return InfoSheetScaffold(
      scrollController: scrollController,
      children: [
        const SizedBox(height: 16),

        // Морская локация (П3): осмотр с воды.
        if (isBoat) ...[
          const BoatBadge(),
          const SizedBox(height: 8),
        ],

        ImageGallery(
          imagePaths: imagePaths,
          islandId: islandId,
          height: 176,
          borderRadius: 14,
          // Как на деталях POI (B3.6): у маршрута Гемилера
          // 229 кадров — карусель в шторке листать
          // нереально; 12 кадров + плитка «Все фото (N)».
          maxCarouselFrames: 12,
        ),

        const SizedBox(height: 16),

        // Название + звезда «в избранное» — как в шторке POI
        // (P1-3): раньше у маршрута звезды не было вовсе.
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                trail.name,
                style: AppText.h2.copyWith(
                ),
              ),
            ),
            const SizedBox(width: 8),
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: FavoriteButton(
                itemId: trail.id,
                islandId: islandId,
                cascadeKeys: cascadeKeys,
              ),
            ),
          ],
        ),

        // Длина · точки · рельеф — Wrap (D1): при textScale
        // 1.6 на узких экранах строка из трёх пунктов
        // переносится, а не переполняет. Иконка и подпись
        // держатся вместе — «пункт» не рвётся пополам.
        if (trail.distance != null || poiCount > 0) ...[
          const SizedBox(height: 8),

          Wrap(
            spacing: AppSpace.s,
            runSpacing: 6,
            children: [
              if (trail.distance != null)
                _TrailMetaItem(
                  icon: LucideIcons.ruler,
                  label: formatTrailDistance(trail.distance),
                ),

              if (poiCount > 0)
                _TrailMetaItem(
                  icon: LucideIcons.footprints,
                  label:
                      '$poiCount ${pluralRu(poiCount, 'место', 'места', 'мест')}',
                ),

              // Рельеф трека (П5): только когда GPX несёт
              // высоты — у побережий строки нет.
              if (elevationStats.isNotEmpty)
                _TrailMetaItem(
                  icon: LucideIcons.mountain,
                  label:
                      'подъём +${elevationStats.ascent.round()} м',
                ),
            ],
          ),
        ],

        if (trail.description != null) ...[
          const SizedBox(height: 8),

          // Длинные описания — сворачиваются (P2, 7-й
          // проход): шторка не выше 70% экрана, полный
          // текст разворачивается по кнопке.
          ExpandableText(
            text: trail.description!,
            collapsedLines: 4,
            style: theme.textTheme.bodyMedium,
          ),
        ],

        const SizedBox(height: 16),

        // Полная страница маршрута (A11): шторка закрывается,
        // страница открывается поверх карты.
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton.tonal(
            onPressed: () {
              Navigator.of(context).pop();

              context.push('/trail/${trail.id}?island=$islandId');
            },
            child: const Text('Подробнее'),
          ),
        ),
      ],
    );
  }
}

/// Пункт мета-строки маршрута (D1): иконка и подпись держатся
/// вместе — Wrap переносит по ЦЕЛЫМ пунктам.
class _TrailMetaItem extends StatelessWidget {
  const _TrailMetaItem({required this.icon, required this.label});

  final IconData icon;

  final String label;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);

    final theme = Theme.of(context);

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Icon(icon, size: 16, color: palette.info),

        const SizedBox(width: 6),

        // Пункт уже ширины Wrap урезается эллипсисом: Wrap
        // переносит ЦЕЛЫЕ пункты, один сверхширокий иначе
        // переполнял бы строку (матрица D1, 320×1.6).
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: palette.info,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}
