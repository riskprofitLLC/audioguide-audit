import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/utils/logger.dart';
import '../../../../features/content/models/region_catalog.dart';
import '../../../../features/content/providers/content_providers.dart';
import 'scrollable_chip_rail.dart';


/// Лента переключения регионов.
///
/// Горизонтальная лента чипов в шапке главного экрана: ВСЕ
/// регионы каталога, текущий подсвечен заливкой — у пользователя
/// всегда есть видимый «активный» чип (ментальная модель
/// «я здесь»), а не пустующее место в ленте. Длинные названия
/// не обрезаются — лента прокручивается свайпом. При выборе
/// региона текущая локация ставится на первую локацию региона.
class RegionSwitcher extends ConsumerWidget {

  const RegionSwitcher({super.key});


  @override
  Widget build(BuildContext context, WidgetRef ref) {

    final regionsAsync =
        ref.watch(regionsProvider);

    final currentRegionId =
        ref.watch(currentRegionIdProvider);

    return regionsAsync.when(

      loading: () => const SizedBox.shrink(),

      error: (error, stack) => const SizedBox.shrink(),

      data: (regions) {

        if (regions.length < 2) {

          return const SizedBox.shrink();
        }

        return ScrollableChipRail(
          items: [
            for (final region in regions)
              (id: region.id, label: region.name),
          ],
          activeId: currentRegionId,
          onSelect: (regionId) => _select(ref, regionId),
          icon: kRegionSwitcherIcon,
        );
      },
    );
  }
}


void _select(WidgetRef ref, String regionId) {

  final region = regionById(regionId);

  AppLogger.info(
    '[HomePage] region switch -> $regionId (now ${region.name})',
  );

  ref.read(currentRegionIdProvider.notifier).state = regionId;

  ref.read(currentIslandIdProvider.notifier).state =
      region.locationIds.first;
}


/// Иконка региона на чипах ленты — единая для всех регионов.
const IconData kRegionSwitcherIcon = LucideIcons.mapPinned;