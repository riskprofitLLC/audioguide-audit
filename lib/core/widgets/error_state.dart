import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/theme.dart';

/// Единый стиль пустых/ошибочных состояний (B8, 9-й проход):
/// глиф в круге sandLight, заголовок Prata (h2), пояснение
/// onSurfaceMuted, действие.
///
/// Используют [ErrorState], [NotFoundState], пустое избранное,
/// пустой поиск и заглушка карты — везде одинаковый силуэт
/// вместо четырёх разных.
class StatePlaceholder extends StatelessWidget {
  const StatePlaceholder({
    super.key,
    required this.icon,
    required this.title,
    this.description,
    this.actions = const <Widget>[],
    this.compact = false,
  });

  /// Глиф состояния.
  final IconData icon;

  final String title;

  final String? description;

  /// Кнопки-действия под пояснением.
  final List<Widget> actions;

  /// Компактная вертикаль — для шторок и вложенных секций.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);

    final theme = Theme.of(context);

    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: 24,
        vertical: compact ? 16 : 32,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: compact ? 44 : 56,
            height: compact ? 44 : 56,
            decoration: BoxDecoration(
              color: palette.sandLight,
              shape: BoxShape.circle,
              border: Border.all(color: palette.sand, width: 1),
            ),
            child: Icon(
              icon,
              size: compact ? 20 : 26,
              color: palette.onSurfaceMuted,
            ),
          ),
          SizedBox(height: compact ? 12 : 16),
          Text(
            title,
            textAlign: TextAlign.center,
            style: AppText.h2.copyWith(color: palette.onSurface),
          ),
          if (description != null) ...[
            const SizedBox(height: 6),
            Text(
              description!,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: palette.onSurfaceMuted,
              ),
            ),
          ],
          if (actions.isNotEmpty) ...[
            const SizedBox(height: 16),
            // Несколько действий — столбиком по центру (как в
            // пустом избранном), одно — просто по центру.
            // Отступ — МЕЖДУ действиями, без хвостового (Б13,
            // замечание Sonnet).
            for (var i = 0; i < actions.length; i++) ...[
              actions[i],
              if (i < actions.length - 1)
                const SizedBox(height: AppSpace.xs),
            ],
          ],
        ],
      ),
    );
  }
}

/// Оформленная ошибка загрузки: иконка, человеческий текст,
/// кнопка «Повторить».
///
/// Сырые исключения пользователю не показываем — техническую
/// деталь провайдеры пишут в лог сами. [onRetry] обычно
/// `() => ref.invalidate(провайдер)`.
///
/// В контейнере с ограниченной высотой (превью карты и т.п.)
/// оборачивается в прокрутку — без RenderFlex overflow.
class ErrorState extends StatelessWidget {
  const ErrorState({
    super.key,
    this.message = 'Не удалось загрузить данные',
    this.description = 'Проверьте пакет локации и попробуйте ещё раз',
    this.onRetry,
    this.compact = false,
  });

  final String message;

  final String description;

  final VoidCallback? onRetry;

  /// Компактная вертикаль — для шторок и вложенных секций.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final column = StatePlaceholder(
          icon: LucideIcons.cloudOff,
          title: message,
          description: description,
          compact: compact,
          actions: onRetry == null
              ? const []
              : [
                  OutlinedButton.icon(
                    onPressed: onRetry,
                    icon: const Icon(LucideIcons.rotateCw, size: 16),
                    label: const Text('Повторить'),
                  ),
                ],
        );

        // Свободная высота (списки, центрированный экран) —
        // колонка как есть; в клипе — прокрутка без overflow.
        if (!constraints.maxHeight.isFinite) {
          return column;
        }

        return SingleChildScrollView(child: column);
      },
    );
  }
}

/// Оформленный пустой стейт «объект не найден» с кнопкой
/// «На главную» (глубокая ссылка на удалённый/несуществующий
/// объект не должна показывать голый текст).
class NotFoundState extends StatelessWidget {
  const NotFoundState({
    super.key,
    this.message = 'Объект не найден',
    this.description = 'Возможно, он был удалён из офлайн-пакета',
  });

  final String message;

  final String description;

  @override
  Widget build(BuildContext context) {
    return StatePlaceholder(
      icon: LucideIcons.searchX,
      title: message,
      description: description,
      actions: [
        FilledButton.icon(
          onPressed: () => context.go('/home'),
          icon: const Icon(LucideIcons.house, size: 16),
          label: const Text('На главную'),
        ),
      ],
    );
  }
}
