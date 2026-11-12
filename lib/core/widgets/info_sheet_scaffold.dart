import 'package:flutter/material.dart';

import '../../app/navigation/navigation_shell.dart';
import 'app_bottom_sheet.dart';

/// Каркас информационной шторки объекта на карте (точка, маршрут).
///
/// Держит общий контракт обеих шторок: ручка-захват, кап 70% высоты
/// экрана (часть карты сверху всегда видна — по ней закрывают
/// шторку) и нижний отступ над парящей капсулой навигации.
/// В режиме `DraggableScrollableSheet` «со стопами» (1d, 12-й
/// проход) кап снимается — размером управляет лист.
///
/// Раньше каркас был скопирован в `PoiInfoSheet` и
/// `TrailInfoSheet`: правка отступов/капа расходилась между ними.
class InfoSheetScaffold extends StatelessWidget {
  const InfoSheetScaffold({
    super.key,
    required this.children,
    this.scrollController,
  });

  /// Содержимое шторки; ручку рисует сам каркас.
  final List<Widget> children;

  /// Контроллер прокрутки `DraggableScrollableSheet` (1d, 12-й
  /// проход). Передан — кап 70% снят, размером правит лист.
  final ScrollController? scrollController;

  @override
  Widget build(BuildContext context) {
    final expandable = scrollController != null;

    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: expandable
            ? const BoxConstraints()
            : BoxConstraints(
                maxHeight: MediaQuery.sizeOf(context).height * 0.7,
              ),
        child: Padding(
          // Низ контента — над парящей капсулой навигации: без
          // этого отступа плеер и «Подробнее» прячутся за пилюлю.
          padding: EdgeInsets.fromLTRB(
            20,
            10,
            20,
            NavigationShell.sheetBottomInset(context),
          ),
          child: SingleChildScrollView(
            controller: scrollController,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SheetGrabHandle(),
                ...children,
              ],
            ),
          ),
        ),
      ),
    );
  }
}
