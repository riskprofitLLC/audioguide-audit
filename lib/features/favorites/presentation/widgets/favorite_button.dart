import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme.dart';
import '../../providers/favorites_providers.dart';
import 'favorite_star.dart';


/// Кнопка «в избранное» — круглая пилюля с единой звездой
/// [FavoriteStar] (контурная → залитая, сигнальный акцент).
///
/// Переключает объект в избранное. Ключ избранного
/// составляется из локации и id объекта
/// (`$islandId/$itemId`), чтобы одинаковые id на разных
/// локациях не конфликтовали.
///
/// В тестах ищется по ключу `favorite-button` и tooltip'ам
/// «В избранное» / «Убрать из избранного» (B1).
class FavoriteButton extends ConsumerStatefulWidget {

  const FavoriteButton({
    super.key,
    required this.itemId,
    required this.islandId,
    this.cascadeKeys,
    this.compact = false,
    this.tooltipOn = 'В избранное',
    this.tooltipOff = 'Убрать из избранного',
  });


  final String itemId;

  final String islandId;

  /// Компактная кнопка 44 px — для рядов действий одной высоты
  /// (B5); по умолчанию — «primary floating» 52 px (B1).
  final bool compact;

  /// Дополнительные ключи, которые добавляются в избранное
  /// вместе с [itemId] при включении (например, все
  /// достопримечательности маршрута).
  final Iterable<String>? cascadeKeys;

  final String tooltipOn;

  final String tooltipOff;


  @override
  ConsumerState<FavoriteButton> createState() => _FavoriteButtonState();
}

class _FavoriteButtonState extends ConsumerState<FavoriteButton> {
  /// Импульс тапа по звезде: pop+haptic — только по действию
  /// пользователя, не при подгрузке избранного (P0-4).
  final ValueNotifier<int> _starTap = ValueNotifier<int>(0);

  @override
  void dispose() {
    _starTap.dispose();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {

    final favorites =
        ref.watch(favoritesControllerProvider);

    final favoriteKey =
        '${widget.islandId}/${widget.itemId}';

    final isFavorite =
        favorites.contains(favoriteKey);

    void toggle() {
      _starTap.value++;

      final notifier =
          ref.read(favoritesControllerProvider.notifier);

      notifier.toggle(
        favoriteKey,
        cascadeKeys: widget.cascadeKeys,
      );
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow:
            AppShadows.floating(AppPalette.of(context).onSurface),
      ),
      child: Material(
        color: isFavorite
            ? AppColors.signal
            : AppPalette.of(context).surfaceRaised,
        shape: const CircleBorder(),
        elevation: 0,
        clipBehavior: Clip.antiAlias,
        child: Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: isFavorite
                  ? AppPalette.of(context).accentDark
                  : AppPalette.of(context).sand,
              width: 1,
            ),
          ),
          child: IconButton(
            key: const ValueKey('favorite-button'),
            tooltip: isFavorite ? widget.tooltipOff : widget.tooltipOn,
            icon: FavoriteStar(
              filled: isFavorite,
              size: widget.compact ? 20 : 22,
              filledColor: AppColors.accentOn,
              emptyColor: AppPalette.of(context).onSurface,
              tapSignal: _starTap,
            ),
            color: isFavorite
                ? AppColors.accentOn
                : AppPalette.of(context).onSurface,
            style: IconButton.styleFrom(
              minimumSize: widget.compact
                  ? const Size(44, 44)
                  : const Size(52, 52),
              padding: EdgeInsets.all(widget.compact ? 10 : 14),
            ),
            onPressed: toggle,
          ),
        ),
      ),
    );
  }
}
