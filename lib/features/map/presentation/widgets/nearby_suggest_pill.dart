import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';

import '../../../../app/theme.dart';
import '../../../../core/widgets/floating_pill.dart';

/// Пилюля «Рядом: … Слушать?» (B5.4, 8-й проход; B6, 9-й —
/// единый визуальный язык с мини-плеером: радиус pill, тень
/// floating, значок слева в круге depth, высота ≥48).
///
/// Живёт на карте: автогид в режиме «Предлагать» не перебивает
/// играющий вручную трек — предлагает послушать соседний
/// рассказ. 10 с — и MapPage тихо убирает пилюлю.
class NearbySuggestPill extends StatelessWidget {
  const NearbySuggestPill({
    super.key,
    required this.title,
    required this.onListen,
    required this.onDismiss,
    this.narrow = false,
  });

  final String title;

  /// Узкий экран (≤420): пилюля во всю ширину, заголовок —
  /// до двух строк (A5, 9-й проход) — раньше при боковом обрезе
  /// right:132 заголовку оставалось ~60 px.
  final bool narrow;

  final VoidCallback onListen;

  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final palette = AppPalette.of(context);

    // D2: каркас — единый FloatingPill (радиус pill, тень
    // floating, стекло, значок в круге, тап-цель ≥44).
    return PointerInterceptor(
      child: FloatingPill(
        icon: LucideIcons.audioLines,
        tone: FloatingPillTone.info,
        // Тап по самой пилюле — тоже «слушать»: цель больше
        // маленькой кнопки.
        onTap: onListen,
        semanticsLabel: 'Рядом: $title. Нажмите, чтобы слушать',
        padding: const EdgeInsets.fromLTRB(8, 6, 6, 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Рядом',
                      style: AppText.eyebrowMuted.copyWith(
                        color: palette.info,
                      ),
                    ),
                    Text(
                      title,
                      maxLines: narrow ? 2 : 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: palette.onSurface,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
            if (narrow)
              // Узкий экран: круглая кнопка-иконка вместо текстовой
              // (A5) — «Слушать?» съедала ~142 px ширины.
              Semantics(
                button: true,
                label: 'Слушать: $title',
                child: Tooltip(
                  message: 'Слушать?',
                  excludeFromSemantics: true,
                  child: FilledButton(
                    onPressed: onListen,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(44, 44),
                      padding: EdgeInsets.zero,
                      shape: const CircleBorder(),
                    ),
                    child: const Icon(LucideIcons.play, size: 18),
                  ),
                ),
              )
            else
              Semantics(
                button: true,
                label: 'Слушать: $title',
                child: TextButton(
                  onPressed: onListen,
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    minimumSize: const Size(44, 44),
                  ),
                  child: const Text('Слушать?'),
                ),
              ),
            Semantics(
              button: true,
              label: 'Скрыть предложение',
              child: IconButton(
                tooltip: 'Скрыть',
                onPressed: onDismiss,
                icon: Icon(
                  LucideIcons.x,
                  size: 16,
                  color: palette.onSurface,
                ),
                style: IconButton.styleFrom(
                  minimumSize: const Size(44, 44),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
