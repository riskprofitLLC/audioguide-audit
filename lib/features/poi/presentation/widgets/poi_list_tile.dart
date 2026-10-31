import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/utils/format.dart';
import '../../../../core/widgets/content_tile.dart';
import '../../../../core/widgets/poi_thumbnail.dart';
import '../../../content/models/region_catalog.dart';
import '../../models/poi.dart';
import '../../utils/poi_category.dart';

/// Плитка точки в списках: миниатюра с номером, подзаголовок
/// «категория · аудио 6:33», звезда избранного и переход на
/// страницу точки.
///
/// Общая для главной и страницы маршрута (раньше вёрстка жила
/// только в private-методе главной, и страница маршрута своих
/// точек не показывала вовсе).
///
/// Избранное передаётся снаружи ([isFavorite] + [onFavoriteToggle]):
/// главная мемоизирует набор и не должна подписывать каждую плитку
/// на провайдер избранного.
class PoiListTile extends StatelessWidget {
  const PoiListTile({
    super.key,
    required this.poi,
    required this.islandId,
    required this.isFavorite,
    required this.onFavoriteToggle,
    this.showDivider = true,
    this.heroTag,
  });

  final Poi poi;

  final String islandId;

  /// Точка в избранном (ключ `локация/poi-XX`).
  final bool isFavorite;

  final VoidCallback onFavoriteToggle;

  final bool showDivider;

  /// Hero-тег (A1): главная передаёт тег только первой встрече
  /// точки; null — hero нет (страница маршрута: теги главной живут
  /// в соседней ветке IndexedStack — одинаковые дают «multiple
  /// heroes share the same tag»).
  final String? heroTag;

  @override
  Widget build(BuildContext context) {
    final imagePath = poi.imagePaths.isEmpty
        ? null
        : '${locationAssetBase(islandId)}/images/${poi.imagePaths.first}';

    // Подзаголовок: категория + длительность аудио (B2.4), а не
    // обрезанное описание. audioMs — из poi.json (A8).
    final subtitle = [
      if (poi.category != null) poiCategoryLabel(poi.category!),
      if (poi.audioMs != null && poi.audioMs! > 0)
        'аудио ${formatDurationMs(poi.audioMs!)}',
    ].join(' · ');

    // Описание — только на широких экранах (≥600, B2.4).
    final isWideScreen = MediaQuery.sizeOf(context).width >= 600;

    return ContentTile(
      title: poi.title,
      subtitle: subtitle.isEmpty ? null : subtitle,
      body: isWideScreen ? poi.description : null,
      compact: true,
      showDivider: showDivider,
      dividerIndent: 78,
      leading: PoiThumbnail(
        imagePath: imagePath,
        number: poi.number,
      ),
      heroTag: heroTag,
      isFavorite: isFavorite,
      onFavoriteToggle: onFavoriteToggle,
      onTap: () => context.push('/poi/${poi.id}?island=$islandId'),
      semanticLabel: poi.title,
    );
  }
}
