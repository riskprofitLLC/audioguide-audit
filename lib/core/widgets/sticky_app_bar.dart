import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/theme.dart';
import '../../features/favorites/presentation/widgets/favorite_star.dart';


/// Плавающая шапка страниц деталей (POI/маршрут).
///
/// Пока страница не прокручена — только статус-бар и плавающая
/// пилюля «назад» поверх hero-фото; после прокрутки (~100 px)
/// разворачивается до полной высоты с заголовком и кнопками
/// «дерево навигации», «избранное» и «поделиться».
class StickyAppBar extends StatefulWidget {

  const StickyAppBar({
    super.key,
    required this.showTitle,
    required this.title,
    required this.onBack,
    required this.onFavorite,
    required this.onShare,
    required this.onTree,
    required this.isFavorite,
  });

  final bool showTitle;

  final String title;

  final VoidCallback onBack;
  final VoidCallback onFavorite;
  final VoidCallback onShare;
  final VoidCallback onTree;

  final bool isFavorite;

  @override
  State<StickyAppBar> createState() => _StickyAppBarState();
}

class _StickyAppBarState extends State<StickyAppBar> {
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

    final theme = Theme.of(context);

    final palette = AppPalette.of(context);

    final showTitle = widget.showTitle;

    final topPadding = MediaQuery.of(context).padding.top;

    return Stack(
      children: [
        AnimatedPositioned(
          duration: AppMotion.fast,
          curve: AppMotion.curve,
          top: 0,
          left: 0,
          right: 0,
          height: showTitle ? kToolbarHeight + topPadding : topPadding,
          child: AnimatedOpacity(
            duration: AppMotion.fast,
            curve: AppMotion.curve,
            opacity: showTitle ? 1.0 : 0.0,
            child: IgnorePointer(
              ignoring: !showTitle,
              child: Container(
                decoration: BoxDecoration(
                  // Ролевые поверхности (B5).
                  color: AppPalette.of(context).surfaceRaised,
                  border: Border(
                    bottom: BorderSide(
                      color: AppPalette.of(context).sand.withValues(alpha: 0.9),
                      width: 1,
                    ),
                  ),
                  boxShadow: AppShadows.card(palette.onSurface),
                ),
                child: SafeArea(
                  bottom: false,
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(LucideIcons.chevronLeft),
                        onPressed: widget.onBack,
                        tooltip: 'Назад',
                      ),
                      if (showTitle)
                        Expanded(
                          child: Text(
                            widget.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      IconButton(
                        icon: const Icon(LucideIcons.listTree),
                        onPressed: widget.onTree,
                        tooltip: 'Навигация по проекту',
                      ),
                      IconButton(
                        icon: FavoriteStar(
                          filled: widget.isFavorite,
                          size: 22,
                          tapSignal: _starTap,
                        ),
                        onPressed: () {
                          _starTap.value++;

                          widget.onFavorite();
                        },
                        tooltip: widget.isFavorite
                            ? 'Убрать из избранного'
                            : 'В избранное',
                      ),
                      IconButton(
                        icon: const Icon(LucideIcons.share2),
                        onPressed: widget.onShare,
                        tooltip: 'Поделиться',
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),

        // Плавающая пилюля «назад» — видна, пока свёрнута шапка
        // (hero-фото в деталях). Прячется при развёрнутой шапке,
        // чтобы не дублировать её кнопку «назад».
        Positioned(
          top: topPadding + 8,
          left: 12,
          child: AnimatedOpacity(
            duration: AppMotion.fast,
            curve: AppMotion.curve,
            opacity: showTitle ? 0.0 : 1.0,
            child: IgnorePointer(
              ignoring: showTitle,
              child: _HeroBackPill(onBack: widget.onBack),
            ),
          ),
        ),
      ],
    );
  }
}

/// Стеклянная пилюля «назад» поверх hero-фото.
class _HeroBackPill extends StatelessWidget {
  const _HeroBackPill({required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    // Тап-цель 44×44 (P1-1, 6-й проход): визуальная пилюля —
    // иконка с паддингом, но цель — полный круг без ужимания.
    final palette = AppPalette.of(context);

    return Semantics(
      label: 'Назад',
      button: true,
      child: Tooltip(
        message: 'Назад',
        child: SizedBox(
          width: 44,
          height: 44,
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadius.pill),
              boxShadow: AppShadows.floating(palette.onSurface),
            ),
            child: Material(
              color: AppPalette.of(context).surfaceRaised.withValues(alpha: 0.94),
              shape: const CircleBorder(),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: onBack,
                child: Center(
                  child: Icon(
                    LucideIcons.chevronLeft,
                    size: 22,
                    color: palette.onSurface,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
