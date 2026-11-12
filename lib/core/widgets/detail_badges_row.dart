import 'package:flutter/material.dart';

import '../../app/theme.dart';
import 'app_badge.dart';

/// Ряд бейджей деталей (POI и маршрут) — единая вёрстка вместо
/// двух копий `Wrap` с одинаковой геометрией.
///
/// Ключ `detail-badges` сохранён: на него опираются тесты
/// (`detail_actions_overlap_test` и проверки бейджей деталей).
class DetailBadgesRow extends StatelessWidget {
  const DetailBadgesRow({
    super.key,
    required this.children,
    this.spacing = 8,
    this.runSpacing = 6,
  });

  final List<Widget> children;

  final double spacing;

  final double runSpacing;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      key: const ValueKey('detail-badges'),
      spacing: spacing,
      runSpacing: runSpacing,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: children,
    );
  }
}

/// Песочный бейдж-плашка деталей (категория, дистанция): тот же
/// язык, что [AppBadge] с вариантом sand.
class DetailSandBadge extends StatelessWidget {
  const DetailSandBadge({
    super.key,
    required this.label,
    this.caps = false,
  });

  final String label;

  /// CAPS-подпись («2,4 КМ») — токен [AppText.label].
  final bool caps;

  @override
  Widget build(BuildContext context) {
    return AppBadge(label: label, caps: caps);
  }
}
