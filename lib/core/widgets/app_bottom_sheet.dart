import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/navigation/navigation_shell.dart';
import '../../app/overlay_tracker.dart';
import '../../app/theme.dart';
import 'glass_icon_button.dart';

/// Единый каркас нижних шторок приложения (B2, 10-й проход).
///
/// Один язык для «Все фото», «Сейчас играет», легенды и настроек:
/// ручка-захват, шапка с заголовком Prata и кнопкой «Закрыть»
/// (тап-цель 44), фон chart, радиус [AppRadius.sheet], нижний
/// отступ над парящей капсулой [NavigationShell.sheetBottomInset]
/// и регистрация в [modalSheetOpenCount] (пилюля мини-плеера
/// живёт НАД Navigator'ом и не должна висеть поверх шторки).
///
/// Два режима роста:
/// - [heightFactor] — фиксированная доля экрана (например 0.92
///   у «Все фото»): шторка всегда одной высоты, тело скроллится;
/// - [maxHeightFactor] — потолок (0.85 у легенды/настроек):
///   шторка строится по контенту, не выше доли экрана.
///
/// [expandBody] — тело управляет своим скроллом само (сетка
/// «Все фото»): каркас не оборачивает его в SingleChildScrollView.
Future<void> showAppBottomSheet(
  BuildContext context, {
  required String title,
  required WidgetBuilder builder,
  double? heightFactor,
  double maxHeightFactor = 0.85,
  bool expandBody = false,
  EdgeInsets contentPadding = const EdgeInsets.fromLTRB(24, 6, 24, 0),
  String closeTooltip = 'Закрыть',
}) {
  // Мини-плеер прячет пилюлю на время модальной шторки — общий
  // счётчик, как у дерева/шторок POI.
  modalSheetOpenCount.value++;

  try {
    // Синхронный throw контекста без Navigator (Б1, замечание
    // Sonnet) не должен оставлять счётчик поднятым навсегда —
    // иначе пилюля мини-плеера пряталась бы до перезапуска.
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      sheetAnimationStyle: AppTheme.sheetAnimationStyle,
      builder: (sheetContext) => AppBottomSheet(
        title: title,
        heightFactor: heightFactor,
        maxHeightFactor: maxHeightFactor,
        expandBody: expandBody,
        contentPadding: contentPadding,
        closeTooltip: closeTooltip,
        child: builder(sheetContext),
      ),
    ).whenComplete(() {
      modalSheetOpenCount.value--;
    });
  } catch (error) {
    modalSheetOpenCount.value--;

    rethrow;
  }
}

/// Каркас шторки (см. [showAppBottomSheet]).
class AppBottomSheet extends StatelessWidget {
  const AppBottomSheet({
    super.key,
    required this.title,
    required this.child,
    this.heightFactor,
    this.maxHeightFactor = 0.85,
    this.expandBody = false,
    this.contentPadding = const EdgeInsets.fromLTRB(24, 6, 24, 0),
    this.closeTooltip = 'Закрыть',
  });

  /// Заголовок шапки (Prata).
  final String title;

  /// Тело шторки.

  /// Фиксированная доля экрана (0.92) — шторка одной высоты.
  final double? heightFactor;

  /// Потолок высоты при авторосте по контенту.
  final double maxHeightFactor;

  /// Тело само скроллится (сетка): без обёртки SingleChildScrollView.
  final bool expandBody;

  /// Внутренние отступы тела (нижний отступ над капсулой каркас
  /// добавляет сам).
  final EdgeInsets contentPadding;

  /// Подпись кнопки закрытия.
  final String closeTooltip;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final fixedHeight = heightFactor;

    final body = expandBody
        ? child
        : SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              contentPadding.left,
              contentPadding.top,
              contentPadding.right,
              // Низ контента — над парящей капсулой навигации:
              // без отступа последние строки прячутся за пилюлю.
              NavigationShell.sheetBottomInset(context) +
                  contentPadding.bottom,
            ),
            child: child,
          );

    final column = Column(
      mainAxisSize:
          fixedHeight != null ? MainAxisSize.max : MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SheetGrabHandle(),

        _SheetHeader(
          title: title,
          closeTooltip: closeTooltip,
          onClose: () => Navigator.of(context).pop(),
        ),

        if (fixedHeight != null)
          Expanded(child: body)
        else
          // Flexible (loose): тело растёт по контенту, но при
          // достижении потолка maxHeightFactor — скроллится,
          // а не переполняет колонку (B2, 10-й проход).
          Flexible(child: body),
      ],
    );

    final sheet = Container(
      decoration: BoxDecoration(
        // Фон шторки — из темы (B5, 11-й проход).
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(AppRadius.sheet),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: SafeArea(
        top: false,
        child: column,
      ),
    );

    if (fixedHeight != null) {
      return FractionallySizedBox(
        heightFactor: fixedHeight,
        child: sheet,
      );
    }

    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * maxHeightFactor,
      ),
      child: sheet,
    );
  }
}

/// Ручка-захват: единый силуэт для всех шторок (B2).
///
/// Публичная — её используют и шторки вне `AppBottomSheet`
/// (инфо-шторки POI/маршрута, дерево навигации): раньше силуэт
/// был скопирован в четырёх местах и расходился при правках.
class SheetGrabHandle extends StatelessWidget {
  const SheetGrabHandle({super.key});

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);

    return Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 4),
      child: Center(
        child: SizedBox(
          width: 40,
          height: 4,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: palette.sand,
              borderRadius: const BorderRadius.all(Radius.circular(2)),
            ),
          ),
        ),
      ),
    );
  }
}

/// Шапка шторки: заголовок Prata + кнопка «Закрыть» 44.
class _SheetHeader extends StatelessWidget {
  const _SheetHeader({
    required this.title,
    required this.closeTooltip,
    required this.onClose,
  });

  final String title;

  final String closeTooltip;

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 12, 10),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              // Prata — заголовки шторок, как прежде у легенды
              // и настроек (headlineMedium);
              style: AppText.h2.copyWith(color: palette.onSurface),
            ),
          ),
          const SizedBox(width: 8),
          GlassIconButton(
            icon: LucideIcons.x,
            onTap: onClose,
            tooltip: closeTooltip,
            floating: false,
          ),
        ],
      ),
    );
  }
}
