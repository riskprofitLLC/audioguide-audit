import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/utils/capitalize.dart';

import '../../../../core/utils/logger.dart';
import '../../../../core/widgets/error_state.dart';
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

      // Ошибка каталога НЕ молчит (C11): показываем существующее
      // пустое состояние вместо необъяснимого отсутствия чипов.
      error: (error, stack) => const StatePlaceholder(
        compact: true,
        icon: LucideIcons.anchor,
        title: 'Локации недоступны',
        description: 'Каталог не загрузился — переключение локации '
            'временно недоступно.',
      ),

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
          // Локации — такие же крупные кнопки, как лента регионов
          // (замечание владельца: чипы локаций были мелкими).
          // Активный чип — общей заливкой info/onInfo: прежняя
          // заливка sandLight в тёмной теме почти сливалась с
          // фоном (#14252F на #0B1B26) и выбор локации был не
          // виден.
          tall: true,
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