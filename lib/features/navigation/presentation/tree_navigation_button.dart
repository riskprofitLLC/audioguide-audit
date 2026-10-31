import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/widgets/glass_icon_button.dart';
import 'tree_navigation_sheet.dart';


/// Плавающая кнопка «дерево навигации» — быстрый доступ к
/// древовидной структуре проекта (регионы → локации → маршруты
/// → POI). На главной встроена в шапку региона (без тени),
/// на карте и страницах деталей — парит над контентом
/// (`floating: true`, мягкая тень).
///
/// По тапу открывает нижнюю панель [showTreeNavigationSheet].
class TreeNavigationButton extends StatelessWidget {

  const TreeNavigationButton({
    super.key,
    this.floating = true,
  });


  /// Парит ли кнопка над контентом (тень + лёгкая «стеклянность»).
  final bool floating;


  @override
  Widget build(BuildContext context) {
    return GlassIconButton(
      tooltip: 'Навигация по проекту',
      icon: LucideIcons.listTree,
      floating: floating,
      onTap: () => showTreeNavigationSheet(context),
    );
  }
}
