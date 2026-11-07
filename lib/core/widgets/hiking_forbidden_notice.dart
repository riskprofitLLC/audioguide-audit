import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'notice_banner.dart';

/// Стандартная формулировка предупреждения, когда в манифесте
/// локации нет своего `trailNotice`.
const String kHikingForbiddenNotice =
    'Остров является охраняемой исторической зоной. '
    'Осмотр только с воды.';

/// Предупреждение «Пешие маршруты запрещены» (флаг манифеста
/// локации `hikingForbidden`, сейчас — Кекова).
///
/// Единый виджет для главной и карты: раньше это были две копии с
/// РАЗНЫМ текстом по умолчанию (главная — «Остров является
/// охраняемой исторической зоной…», карта — «Остров — охраняемая
/// историческая зона…»): один и тот же случай читался по-разному.
class HikingForbiddenNotice extends StatelessWidget {
  const HikingForbiddenNotice({
    super.key,
    this.notice,
    this.compact = false,
    this.floating = false,
  });

  /// Текст из манифеста (`trailNotice`); null — [kHikingForbiddenNotice].
  final String? notice;

  /// Плотный вариант (карта: баннер не должен закрывать полотно).
  final bool compact;

  /// «Плавающая» тень (баннер лежит поверх карты).
  final bool floating;

  @override
  Widget build(BuildContext context) {
    return NoticeBanner(
      variant: NoticeBannerVariant.warning,
      icon: LucideIcons.ban,
      title: 'Пешие маршруты запрещены',
      message: notice ?? kHikingForbiddenNotice,
      compact: compact,
      floating: floating,
    );
  }
}
