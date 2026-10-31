import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme.dart';
import '../../../../features/favorites/presentation/widgets/favorite_star.dart';
import '../../../../features/favorites/providers/favorites_providers.dart';


/// Одна звёздочка-фильтр на всю локацию.
///
/// При включении (сигнальная) главный экран показывает только избранные
/// достопримечательности — как внутри каждого маршрута, так и
/// в группе «Вне маршрута». Состояние общее для локации,
/// хранится в `islandStarFilterProvider` (ключ `'$islandId'`).
class IslandStarFilter extends ConsumerStatefulWidget {

  const IslandStarFilter({
    super.key,
    required this.islandId,
    required this.filterOn,
  });


  final String islandId;

  final bool filterOn;


  @override
  ConsumerState<IslandStarFilter> createState() => _IslandStarFilterState();
}

class _IslandStarFilterState extends ConsumerState<IslandStarFilter> {
  /// Импульс тапа: pop+haptic только по нажатию (P0-4).
  final ValueNotifier<int> _starTap = ValueNotifier<int>(0);

  @override
  void dispose() {
    _starTap.dispose();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filterOn = widget.filterOn;

    return IconButton(
      tooltip: filterOn
          ? 'Показать все достопримечательности локации'
          : 'Показать только избранные',
      icon: FavoriteStar(
        filled: filterOn,
        size: 22,
        filledColor: AppColors.signalDark,
        emptyColor: AppPalette.of(context).onSurfaceMuted,
        tapSignal: _starTap,
      ),
      onPressed: () {
        _starTap.value++;

        final notifier =
            ref.read(islandStarFilterProvider.notifier);

        final next = Set<String>.of(notifier.state);

        if (next.contains(widget.islandId)) {
          next.remove(widget.islandId);
        } else {
          next.add(widget.islandId);
        }

        notifier.state = next;
      },
    );
  }
}
