import 'dart:math';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../app/theme.dart';
import '../../../../core/widgets/floating_pill.dart';
import '../../../trails/utils/format_distance.dart';
import 'trail_navigation_card.dart' show compassDirectionWords;


/// Плашка «ближайший POI» на карте: курс на точку (П2, 12-й
/// проход) — стрелка и дистанция, рядом румб «на северо-запад».
///
/// B4 (18-й проход): стрелка ВСЕГДА показывает направление
/// ОТНОСИТЕЛЬНО ЭКРАНА КАРТЫ — азимут на точку минус текущий
/// bearing камеры: north-up (bearing 0) — абсолютный азимут,
/// course-up (карта повёрнута по движению) — «куда на экране».
/// Подпись румбом остаётся АБСОЛЮТНОЙ (компасной). Тап —
/// подлететь к точке и открыть её шторку (B4, 17-го).
class NearestPoiChip extends StatelessWidget {

  const NearestPoiChip({
    super.key,
    required this.title,
    required this.distance,
    this.bearing,
    this.mapBearing = 0,
    this.onTap,
  });


  final String title;


  final double distance;


  /// Азимут на точку (0 — север). `null` — позиции не было,
  /// стрелка статична, румба нет.
  final double? bearing;


  /// Текущий bearing камеры (0 — «север вверх»): стрелка
  /// поворачивается вместе с картой (B4). Обновляется отдельно
  /// (ValueListenable), без перестройки всей карты.
  final double mapBearing;


  /// Тап по чипу: подлететь к точке/открыть её шторку (B4).
  final VoidCallback? onTap;


  @override
  Widget build(BuildContext context) {

    final theme = Theme.of(context);

    final palette = AppPalette.of(context);

    // Относительно экрана: азимут на точку минус поворот карты.
    final effectiveAngle = bearing == null
        ? 0.0
        : (bearing! - mapBearing + 360) % 360;

    final label = bearing == null
        ? formatTrailDistance(distance)
        : '${formatTrailDistance(distance)} · '
            '${compassDirectionWords(bearing!)}';

    // D2: каркас — FloatingPill; ведущий элемент — повёрнутая
    // стрелка курса (не круг: направление читается мгновенно).
    return FloatingPill(
      tone: FloatingPillTone.neutral,
      onTap: onTap,
      semanticsLabel: 'Ближайшая точка: $title, '
          '${bearing == null ? formatTrailDistance(distance) : label}. '
          'Стрелка указывает на точку',
      tooltip: 'Стрелка указывает на точку',
      padding: const EdgeInsets.symmetric(
        horizontal: 14,
        vertical: 9,
      ),
      leading: Transform.rotate(
        angle: effectiveAngle * pi / 180,
        child: Icon(
          LucideIcons.navigation2,
          size: 16,
          color: palette.info,
        ),
      ),
      gap: 7,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Название: обрезается эллипсисом — слот верхнего
          // левого угла ограничен right:76, длинные имена
          // точек на узких экранах не должны переполнять чип.
          Flexible(
            fit: FlexFit.loose,
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: 180,
              ),
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: palette.onSurface,
                ),
              ),
            ),
          ),

          const SizedBox(width: 8),

          // Дистанция + абсолютный румб (П2): тоже гибкая —
          // при textScale 1.6 подпись обрезается, а не льётся
          // за край.
          Flexible(
            fit: FlexFit.loose,
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(
                color: palette.info,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
