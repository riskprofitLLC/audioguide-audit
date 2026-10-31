import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/utils/capitalize.dart';

import '../../../../app/theme.dart';
import '../../../../core/utils/logger.dart';
import '../../../../features/content/providers/content_providers.dart';
import 'scrollable_chip_rail.dart';


/// Лента переключения локаций внутри текущего региона.
///
/// Показывается под шапкой региона: чипы с названиями локаций
/// (островов и прибрежных зон), входящих в выбранный регион.
/// Текущая локация подсвечена заливкой, длинные названия не
/// обрезаются — лента прокручивается свайпом.
class LocationSwitcher extends ConsumerWidget {

  const LocationSwitcher({super.key});


  @override
  Widget build(BuildContext context, WidgetRef ref) {

    final locationsAsync =
        ref.watch(regionLocationsProvider);

    final currentIslandId =
        ref.watch(currentIslandIdProvider);

    return locationsAsync.when(

      loading: () => const SizedBox.shrink(),

      error: (error, stack) => const SizedBox.shrink(),

      data: (locations) {

        if (locations.length < 2) {

          return const SizedBox.shrink();
        }

        return ScrollableChipRail(
          items: [
            for (final location in locations)
              (id: location.id, label: capitalize(location.name)),
          ],
          activeId: currentIslandId,
          onSelect: (locationId) => _select(ref, locationId),
          icon: LucideIcons.anchor,
          activeFill: AppPalette.of(context).sandLight,
          activeTextColor: AppPalette.of(context).onSurface,
          activeIconColor: AppColors.depth,
        );
      },
    );
  }
}


void _select(WidgetRef ref, String locationId) {

  AppLogger.info(
    '[HomePage] location switch -> $locationId',
  );

  ref.read(currentIslandIdProvider.notifier).state = locationId;
}