import 'package:flutter/material.dart';

/// Центрированная колонка контента с ограничением ширины.
///
/// На широких экранах (web/планшет) списки и текст не растягиваются
/// на всю ширину окна: читаемый блок ≤ 720 px стоит по центру,
/// как колонка журнала. На узких экранах ограничение не работает
/// и вёрстка не меняется.
class ContentColumn extends StatelessWidget {
  const ContentColumn({super.key, required this.child});

  /// Максимальная ширина читаемого блока.
  static const double maxWidth = 720;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: maxWidth),
        child: child,
      ),
    );
  }
}
