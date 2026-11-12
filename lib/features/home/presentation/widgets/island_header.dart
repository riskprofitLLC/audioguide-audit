import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../app/theme.dart';

/// Шапка главного экрана — титульная страница атласа.
///
/// Редизайн «Атлас»: без карточки и градусных тиков — чистый
/// текст на фоне листа, тонкая иконка-компас, название региона
/// и подстрока «море · страна · издание». Компактная по высоте
/// (замечание владельца: блок с заголовком занимал большую часть
/// экрана): подстрока сверху одним рядом, заголовок — [AppText.h1]
/// на всю ширину и одной строкой, издание — подписью, не пилюлей.
class IslandHeader extends StatelessWidget {

  const IslandHeader({
    super.key,
    required this.islandName,
    this.eyebrow = 'СРЕДИЗЕМНОЕ МОРЕ · ТУРЦИЯ',
    this.version,
    this.action,
  });


  final String islandName;

  /// Eyebrow-подпись — море и страна из манифеста региона.
  final String eyebrow;

  final int? version;

  final Widget? action;


  @override
  Widget build(BuildContext context) {

    final palette = AppPalette.of(context);

    return Column(
      // min: шапка занимает ровно свою высоту, а не растягивается
      // на всю доступную (замечание владельца про высоту блока).
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [

        // Подстрока: компас · море · страна · издание и кнопка
        // действия — всё одним рядом. Пилюля версии убрана: она
        // удваивала высоту шапки. Длинное море режется эллипсисом
        // раньше издания.
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [

            Icon(
              LucideIcons.compass,
              size: 22,
              color: palette.info,
            ),

            const SizedBox(width: AppSpace.xs),

            Flexible(
              child: Text(
                eyebrow,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppText.eyebrow.copyWith(
                  letterSpacing: 1.6,
                  color: palette.info,
                ),
              ),
            ),

            const SizedBox(width: AppSpace.xs),

            Text(
              version != null ? 'Изд. $version' : 'офлайн-пакет',
              style: AppText.eyebrow.copyWith(
                letterSpacing: 1.2,
                color: palette.onSurfaceMuted,
              ),
            ),

            if (action != null) ...[
              const SizedBox(width: AppSpace.xs),
              action!,
            ],
          ],
        ),

        const SizedBox(height: AppSpace.xs),

        // Название региона — на ВСЮ ширину контента и одной
        // строкой (h1 28 вместо display 40): в ряду с компасом и
        // кнопкой даже 28 px переносились на две строки, а под
        // подстрокой занимают ровно одну.
        Text(
          islandName,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: AppText.h1.copyWith(
            height: 1.1,
            color: palette.onSurface,
          ),
        ),
      ],
    );
  }
}
