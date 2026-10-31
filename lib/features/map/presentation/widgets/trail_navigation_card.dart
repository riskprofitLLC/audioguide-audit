import 'dart:math';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../gps/services/trail_navigator.dart';
import '../../../trails/utils/format_distance.dart';
import '../../../../app/theme.dart';

/// Компасное направление словами (B4.5): 8 румбов от
/// «на север» до «на северо-запад».
String compassDirectionWords(double bearing) {
  const names = [
    'на север',
    'на северо-восток',
    'на восток',
    'на юго-восток',
    'на юг',
    'на юго-запад',
    'на запад',
    'на северо-запад',
  ];

  final index = (((bearing + 22.5) % 360) / 45).floor();

  return names[index];
}

/// Карточка навигации по маршруту на карте.
///
/// Показывает активный маршрут, расстояние до его линии,
/// статус «на маршруте / вне маршрута» и направление движения.
class TrailNavigationCard extends StatelessWidget {

  const TrailNavigationCard({
    super.key,
    required this.state,
  });


  final TrailNavigationState state;


  @override
  Widget build(BuildContext context) {

    final theme = Theme.of(context);

    final palette = AppPalette.of(context);

    final statusColor = state.offRoute
        ? theme.colorScheme.error
        : AppColors.success;

    final statusText = state.offRoute
        ? 'Вне маршрута'
        : 'На маршруте';

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        boxShadow: AppShadows.floating(palette.onSurface),
      ),
      child: Material(
        color: palette.surfaceRaised.withValues(alpha: 0.94),
        elevation: 0,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 10,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [

              // Стрелка азимута (B4.5): navigation2-глиф,
              // повёрнутый по направлению движения. A3 (17-й
              // проход): navigation2 остриём на СЕВЕР — старый
              // navigation смотрел на северо-восток и врал на 45°.
              Transform.rotate(
                angle: state.bearing * pi / 180,
                child: Icon(
                  LucideIcons.navigation2,
                  color: palette.info,
                  size: 30,
                ),
              ),

            const SizedBox(width: 12),

            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [

                  Text(
                    state.trail.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),

                  const SizedBox(height: 4),

                  Text(
                    // Километры от 1000 м — единый формат с остальными
                    // дистанциями приложения.
                    state.offRoute
                        ? 'Отклонение ${formatTrailDistance(state.distanceToTrack)}'
                        : 'До маршрута ${formatTrailDistance(state.distanceToTrack)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall,
                  ),

                  const SizedBox(height: 2),

                  // Компасное направление словами (B4.5): «на
                  // северо-восток» — читабельнее градусов. При
                  // движении против порядка вершин азимут уже
                  // инвертирован к «следующей для человека» точке
                  // (A17, 17-й проход) — подписка остаётся верной.
                  Text(
                    state.reversed
                        ? 'Идти назад: ${compassDirectionWords(state.bearing)}'
                        : 'Идти ${compassDirectionWords(state.bearing)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: palette.onSurfaceMuted,
                    ),
                  ),

                  // П4 (29-й проход): ближайший манёвр —
                  // «через N м направо» / «до конца маршрута».
                  if (state.maneuver != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      state.maneuver!.isFinish
                          ? 'До конца маршрута ${formatTrailDistance(state.maneuver!.distanceMeters)}'
                          : 'Через ${formatTrailDistance(state.maneuver!.distanceMeters)} — ${state.maneuver!.instruction}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: palette.info,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ],
              ),
            ),

            const SizedBox(width: 12),

            Column(
              mainAxisSize: MainAxisSize.min,
              children: [

                Text(
                  '${state.bearing.round()}°',
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: palette.info,
                    fontWeight: FontWeight.bold,
                  ),
                ),

                const SizedBox(height: 2),

                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(AppRadius.chip),
                  ),
                  child: Text(
                    statusText,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: statusColor,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
        ),
      ),
    );
  }
}
