import 'package:flutter/material.dart';

import '../../app/navigation/navigation_shell.dart';
import '../../app/overlay_tracker.dart';

/// Показывает SnackBar НАД парящей капсулой навигации.
///
/// Обычный floating SnackBar встаёт у нижней кромки экрана, а
/// капсула навигации парит поверх неё — кнопка действия
/// («Отменить») оказывается перекрытой и недоступной (P0-2,
/// 6-й проход). Хелпер задаёт нижний отступ
/// [NavigationShell.sheetBottomInset] (на десктопе капсулы нет —
/// обычные 24) и поднимает плашку над видимым мини-плеером.
/// Стиль берётся из snackBarTheme приложения.
void showAppSnackBar(
  BuildContext context,
  String message, {
  String? actionLabel,
  VoidCallback? onAction,
  Duration duration = const Duration(seconds: 4),
}) {
  // Пока мини-плеер виден, он занимает ту же зону над капсулой.
  final lift = miniPlayerVisible.value && modalSheetOpenCount.value == 0
      ? 66.0
      : 0.0;

  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(message),
      behavior: SnackBarBehavior.floating,
      duration: duration,
      margin: EdgeInsets.fromLTRB(
        16,
        0,
        16,
        NavigationShell.sheetBottomInset(context) + lift,
      ),
      action: actionLabel == null
          ? null
          : SnackBarAction(
              label: actionLabel,
              onPressed: () {
                onAction?.call();
              },
            ),
    ),
  );
}
